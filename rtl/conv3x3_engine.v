// ---------------------------------------------------------------------------
// conv3x3_engine.v — runtime-programmable 3x3 convolution engine
// Freshly reconstructed from the manuscript's design specification
// (Sec. III-G, Table 3). Original sources lost; independent implementation.
//
// Contract (bit-exact, matches golden/gen_vectors.py):
//   window: 3x3, EDGE-REPLICATED borders
//   acc_k  = sum_i K_k[i] * pix[i]            (signed; |acc| < 2^19)
//   dual   : y = clamp((|acc1| + |acc2|) >> k, 0, 255)     (MODE = 0)
//   single : y = clamp( |acc1|            >> k, 0, 255)     (MODE = 1, SIGNED = 0)
//   signed : y = clamp(  acc1             >> k, 0, 255)     (MODE = 1, SIGNED = 1;
//            negative results clamp to 0, e.g. for sharpening)
//
// AXI4-Lite map: 0x00 CTRL {bit0 EN, bit1 MODE, bit2 SIGNED, [7:4] K};
// 0x04 STATUS {bit0 busy, bit1 coeff-update pending}; 0x08+4i K1[i];
// 0x2C+4i K2[i] (i = 0..8 row-major, signed 8-bit). MODE, SIGNED, K and the
// coefficients are shadowed and commit at the next accepted start-of-frame
// (TUSER) — no mid-frame tear. EN acts immediately: EN = 0 pauses input
// acceptance (TREADY low) and EN = 1 resumes it.
// Reset state: Sobel Gx/Gy, dual, k = 3 (drop-in for the fixed core).
//
// Microarchitecture: every accepted pixel forms a vertical triple
// {top,mid,bot} (row-replication muxed at top/bottom borders); triples shift
// through a 3-deep column pipe; push counter p emits center column p-2 with
// left replication at p == 2; one extra push after EOL replicates the right
// edge; one synthetic row after the last line replicates the bottom edge.
// The identical push algorithm is validated against the numpy golden model
// in golden/rtl_model.py.
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module conv3x3_engine #(
    parameter integer W  = 160,
    parameter integer H  = 120,
    parameter integer CW = 9            // counter width; 2**CW > W+1
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,    // SOF
    input  wire        s_axis_tlast,    // EOL
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tuser,
    output reg         m_axis_tlast,
    input  wire [7:0]  s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [7:0]  s_axil_araddr,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready
);
    // ---------------- shadow + active configuration ----------------
    reg        sh_en, sh_mode, sh_sgn;  reg [3:0] sh_k;
    reg signed [7:0] sh_k1 [0:8], sh_k2 [0:8];
    reg        cfg_pending;
    reg        mode_q, sgn_q;   reg [3:0] k_q;
    reg signed [7:0] k1_q [0:8], k2_q [0:8];
    reg        busy_q;
    reg        commit_pulse;
    integer ii;

    task set_sobel_sh; begin
        sh_k1[0]<=-8'sd1; sh_k1[1]<=8'sd0; sh_k1[2]<=8'sd1;
        sh_k1[3]<=-8'sd2; sh_k1[4]<=8'sd0; sh_k1[5]<=8'sd2;
        sh_k1[6]<=-8'sd1; sh_k1[7]<=8'sd0; sh_k1[8]<=8'sd1;
        sh_k2[0]<=-8'sd1; sh_k2[1]<=-8'sd2; sh_k2[2]<=-8'sd1;
        sh_k2[3]<= 8'sd0; sh_k2[4]<= 8'sd0; sh_k2[5]<= 8'sd0;
        sh_k2[6]<= 8'sd1; sh_k2[7]<= 8'sd2; sh_k2[8]<= 8'sd1;
    end endtask

    // AXI4-Lite write channel (one outstanding)
    reg aw_hs, w_hs;  reg [7:0] awaddr_q;
    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axil_awready<=1'b0; s_axil_wready<=1'b0; s_axil_bvalid<=1'b0;
            s_axil_bresp<=2'b00; aw_hs<=1'b0; w_hs<=1'b0; awaddr_q<=8'd0;
            cfg_pending<=1'b0; sh_en<=1'b1; sh_mode<=1'b0; sh_sgn<=1'b0; sh_k<=4'd3;
            set_sobel_sh;
        end else begin
            s_axil_awready <= (!aw_hs && s_axil_awvalid && !s_axil_awready);
            if (s_axil_awvalid && s_axil_awready) begin aw_hs<=1'b1; awaddr_q<=s_axil_awaddr; end
            s_axil_wready <= (!w_hs && s_axil_wvalid && !s_axil_wready);
            if (s_axil_wvalid && s_axil_wready) w_hs<=1'b1;
            if (aw_hs && w_hs && !s_axil_bvalid) begin
                if (awaddr_q==8'h00) begin
                    sh_en<=s_axil_wdata[0]; sh_mode<=s_axil_wdata[1]; sh_sgn<=s_axil_wdata[2];
                    sh_k<=s_axil_wdata[7:4];
                end else if (awaddr_q>=8'h08 && awaddr_q<=8'h28)
                    sh_k1[(awaddr_q-8'h08)>>2] <= s_axil_wdata[7:0];
                else if (awaddr_q>=8'h2C && awaddr_q<=8'h4C)
                    sh_k2[(awaddr_q-8'h2C)>>2] <= s_axil_wdata[7:0];
                cfg_pending<=1'b1; s_axil_bvalid<=1'b1; s_axil_bresp<=2'b00;
                aw_hs<=1'b0; w_hs<=1'b0;
            end
            if (s_axil_bvalid && s_axil_bready) s_axil_bvalid<=1'b0;
            if (commit_pulse) cfg_pending<=1'b0;
        end
    end
    // AXI4-Lite read channel
    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axil_arready<=1'b0; s_axil_rvalid<=1'b0; s_axil_rdata<=32'd0; s_axil_rresp<=2'b00;
        end else begin
            s_axil_arready <= (!s_axil_rvalid && s_axil_arvalid && !s_axil_arready);
            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid<=1'b1; s_axil_rresp<=2'b00;
                if (s_axil_araddr==8'h00)      s_axil_rdata <= {24'd0, sh_k, 1'b0, sh_sgn, sh_mode, sh_en};
                else if (s_axil_araddr==8'h04) s_axil_rdata <= {30'd0, cfg_pending, busy_q};
                else if (s_axil_araddr>=8'h08 && s_axil_araddr<=8'h28)
                    s_axil_rdata <= {{24{sh_k1[(s_axil_araddr-8'h08)>>2][7]}}, sh_k1[(s_axil_araddr-8'h08)>>2]};
                else if (s_axil_araddr>=8'h2C && s_axil_araddr<=8'h4C)
                    s_axil_rdata <= {{24{sh_k2[(s_axil_araddr-8'h2C)>>2][7]}}, sh_k2[(s_axil_araddr-8'h2C)>>2]};
                else s_axil_rdata <= 32'd0;
            end
            if (s_axil_rvalid && s_axil_rready) s_axil_rvalid<=1'b0;
        end
    end

    // ---------------- streaming core: vertical-triple push pipeline --------
    localparam ST_ROW    = 2'd0;   // accepting a row's pixels
    localparam ST_RFLUSH = 2'd1;   // right-edge replicate push
    localparam ST_BROW   = 2'd2;   // synthetic bottom row (reads buffers)
    localparam ST_BFLUSH = 2'd3;   // bottom row's right-edge push

    reg [1:0]     state;
    reg [CW-1:0]  col_in;          // input column
    reg [15:0]    row_in;          // input row index
    reg [CW-1:0]  pcnt;            // pushes this output row (1..W+1)
    reg [15:0]    row_out;         // center row being emitted
    reg [CW-1:0]  col_ff;          // synthetic-row column
    reg           frame_done_q;

    wire stall = m_axis_tvalid && !m_axis_tready;
    wire ce    = !stall;
    assign s_axis_tready = (state == ST_ROW) && ce && sh_en;   // EN pauses immediately
    wire in_hs = s_axis_tvalid && s_axis_tready;
    wire sof_accept = in_hs && s_axis_tuser;

    always @(posedge aclk) begin                 // config commit at SOF
        if (!aresetn) begin
            mode_q<=1'b0; sgn_q<=1'b0; k_q<=4'd3; commit_pulse<=1'b0;
            k1_q[0]<=-8'sd1;k1_q[1]<=8'sd0;k1_q[2]<=8'sd1;k1_q[3]<=-8'sd2;k1_q[4]<=8'sd0;
            k1_q[5]<=8'sd2;k1_q[6]<=-8'sd1;k1_q[7]<=8'sd0;k1_q[8]<=8'sd1;
            k2_q[0]<=-8'sd1;k2_q[1]<=-8'sd2;k2_q[2]<=-8'sd1;k2_q[3]<=8'sd0;k2_q[4]<=8'sd0;
            k2_q[5]<=8'sd0;k2_q[6]<=8'sd1;k2_q[7]<=8'sd2;k2_q[8]<=8'sd1;
        end else begin
            commit_pulse <= 1'b0;
            if (ce && sof_accept) begin
                mode_q<=sh_mode; sgn_q<=sh_sgn; k_q<=sh_k;
                for (ii=0; ii<9; ii=ii+1) begin k1_q[ii]<=sh_k1[ii]; k2_q[ii]<=sh_k2[ii]; end
                commit_pulse <= 1'b1;
            end
        end
    end

    // line buffers (BRAM-inferable): lb1 = previous row, lb2 = two back
    reg [7:0] lb1 [0:(1<<CW)-1];
    reg [7:0] lb2 [0:(1<<CW)-1];

    // 3-deep triple pipe (t0 oldest .. t2 newest)
    reg [7:0] t0_t,t0_m,t0_b, t1_t,t1_m,t1_b, t2_t,t2_m,t2_b;

    // vertical triple for this push
    reg [7:0] top_px, mid_px, bot_px;
    always @(*) begin
        case (state)
            ST_ROW: begin
                bot_px = s_axis_tdata;
                mid_px = lb1[col_in];
                top_px = (row_in == 16'd1) ? lb1[col_in] : lb2[col_in];
            end
            ST_BROW: begin
                bot_px = lb1[col_ff];                    // replicate last row
                mid_px = lb1[col_ff];
                top_px = (H >= 2) ? lb2[col_ff] : lb1[col_ff];
            end
            default: begin                                // R/B FLUSH: repeat
                bot_px = t2_b; mid_px = t2_m; top_px = t2_t;
            end
        endcase
    end

    wire push = ce && ( (state==ST_ROW    && in_hs && row_in >= 16'd1) ||
                        (state==ST_RFLUSH)                              ||
                        (state==ST_BROW)                                ||
                        (state==ST_BFLUSH) );

    always @(posedge aclk) begin
        if (!aresetn) begin
            state<=ST_ROW; col_in<={CW{1'b0}}; row_in<=16'd0; pcnt<={CW{1'b0}};
            row_out<=16'd0; col_ff<={CW{1'b0}}; busy_q<=1'b0; frame_done_q<=1'b0;
        end else if (ce) begin
            if (push) begin
                t0_t<=t1_t; t0_m<=t1_m; t0_b<=t1_b;
                t1_t<=t2_t; t1_m<=t2_m; t1_b<=t2_b;
                t2_t<=top_px; t2_m<=mid_px; t2_b<=bot_px;
                pcnt <= pcnt + 1'b1;
            end
            case (state)
            ST_ROW: if (in_hs) begin
                if (s_axis_tuser) begin
                    row_in<=16'd0; busy_q<=1'b1; frame_done_q<=1'b0;
                    row_out<=16'd0; pcnt<={CW{1'b0}};
                end
                lb2[col_in] <= lb1[col_in];
                lb1[col_in] <= s_axis_tdata;
                if (s_axis_tlast) begin
                    col_in <= {CW{1'b0}};
                    if (row_in >= 16'd1) state <= ST_RFLUSH;   // emit col W-1
                    row_in <= (s_axis_tuser ? 16'd0 : row_in) + 16'd1;
                end else begin
                    col_in <= col_in + 1'b1;
                    if (s_axis_tuser) row_in <= 16'd0;
                end
            end
            ST_RFLUSH: begin
                if (row_out == H-2 && row_in == H) begin       // last real row
                    state<=ST_BROW; col_ff<={CW{1'b0}};
                    row_out<=row_out+1'b1; pcnt<={CW{1'b0}};
                end else begin
                    state<=ST_ROW;
                    row_out<=row_out+1'b1; pcnt<={CW{1'b0}};
                end
            end
            ST_BROW: begin
                if (col_ff == W-1) state<=ST_BFLUSH;
                col_ff <= col_ff + 1'b1;
            end
            ST_BFLUSH: begin
                state<=ST_ROW; busy_q<=1'b0; frame_done_q<=1'b1;
                pcnt<={CW{1'b0}};
            end
            endcase
        end
    end

    // ---------------- MAC stage (two-stage: products, then adder trees) --
    // The cycle after push #p, taps (t0,t1,t2) hold triples (p-2, p-1, p):
    // stage B registers the 18 products (mapped to DSP48E1 slices), stage C
    // sums each 9-term tree; center column p-2, left replication at p == 2.
    // Semantics proven in scripts/rtl_model.py; latency-only change.
    reg               push_q;
    reg [CW-1:0]      pcnt_q;        // p: pcnt value AFTER the push
    reg [15:0]        rowp_q;
    reg               vB_q;
    reg [15:0]        rowB_q;
    reg [CW-1:0]      ccB_q;
    (* use_dsp = "yes" *) reg signed [15:0] pr1 [0:8];
    (* use_dsp = "yes" *) reg signed [15:0] pr2 [0:8];
    reg               v1_q;
    reg [15:0]        row1_q;
    reg [CW-1:0]      cc1_q;
    reg signed [19:0] acc1_q, acc2_q;
    reg               sofp_q;
    reg [3:0]         kB_q, kC_q, kD_q;
    reg               mB_q, mC_q, sB_q, sC_q;
    reg               vD_q;
    reg [20:0]        mag_q;
    reg [15:0]        rowD_q;
    reg [CW-1:0]      ccD_q;

    // left-border replication flag, registered alongside pcnt_q
    // (lrep_q == (pcnt_q == 2) every cycle; keeps the compare off the
    //  window-mux -> DSP input path)
    reg lrep_q;
    wire lrep = lrep_q;
    wire [7:0] p0 = lrep ? t1_t : t0_t,  p1 = t1_t,  p2 = t2_t;
    wire [7:0] p3 = lrep ? t1_m : t0_m,  p4 = t1_m,  p5 = t2_m;
    wire [7:0] p6 = lrep ? t1_b : t0_b,  p7 = t1_b,  p8 = t2_b;

    always @(posedge aclk) begin
        if (!aresetn) begin
            push_q<=1'b0; pcnt_q<={CW{1'b0}}; lrep_q<=1'b0; rowp_q<=16'd0;
            vB_q<=1'b0; rowB_q<=16'd0; ccB_q<={CW{1'b0}};
            v1_q<=1'b0; acc1_q<=20'sd0; acc2_q<=20'sd0;
            row1_q<=16'd0; cc1_q<={CW{1'b0}};
            for (ii=0; ii<9; ii=ii+1) begin pr1[ii]<=16'sd0; pr2[ii]<=16'sd0; end
        end else if (ce) begin
            // stage A: push bookkeeping
            push_q <= push;
            if (push) begin
                pcnt_q <= pcnt + 1'b1;
                lrep_q <= (pcnt == {{(CW-1){1'b0}}, 1'b1});   // pcnt + 1 == 2
                rowp_q <= row_out;
            end
            // stage B: 18 registered products (post-push taps)
            pr1[0]<=k1_q[0]*$signed({1'b0,p0}); pr1[1]<=k1_q[1]*$signed({1'b0,p1});
            pr1[2]<=k1_q[2]*$signed({1'b0,p2}); pr1[3]<=k1_q[3]*$signed({1'b0,p3});
            pr1[4]<=k1_q[4]*$signed({1'b0,p4}); pr1[5]<=k1_q[5]*$signed({1'b0,p5});
            pr1[6]<=k1_q[6]*$signed({1'b0,p6}); pr1[7]<=k1_q[7]*$signed({1'b0,p7});
            pr1[8]<=k1_q[8]*$signed({1'b0,p8});
            pr2[0]<=k2_q[0]*$signed({1'b0,p0}); pr2[1]<=k2_q[1]*$signed({1'b0,p1});
            pr2[2]<=k2_q[2]*$signed({1'b0,p2}); pr2[3]<=k2_q[3]*$signed({1'b0,p3});
            pr2[4]<=k2_q[4]*$signed({1'b0,p4}); pr2[5]<=k2_q[5]*$signed({1'b0,p5});
            pr2[6]<=k2_q[6]*$signed({1'b0,p6}); pr2[7]<=k2_q[7]*$signed({1'b0,p7});
            pr2[8]<=k2_q[8]*$signed({1'b0,p8});
            vB_q  <= push_q && (pcnt_q >= 2);
            ccB_q <= pcnt_q - 2'd2;
            rowB_q<= rowp_q;
            kB_q  <= k_q;
            mB_q  <= mode_q;
            sB_q  <= sgn_q;
            // stage C: adder trees
            acc1_q <= pr1[0]+pr1[1]+pr1[2]+pr1[3]+pr1[4]+pr1[5]+pr1[6]+pr1[7]+pr1[8];
            acc2_q <= pr2[0]+pr2[1]+pr2[2]+pr2[3]+pr2[4]+pr2[5]+pr2[6]+pr2[7]+pr2[8];
            v1_q   <= vB_q;
            cc1_q  <= ccB_q;
            row1_q <= rowB_q;
            kC_q   <= kB_q;
            mC_q   <= mB_q;
            sC_q   <= sB_q;
        end
    end

    // ---------------- stage D: magnitude / bypass (registered) -----------
    wire [19:0] a1 = acc1_q[19] ? (~acc1_q + 1'b1) : acc1_q;
    wire [19:0] a2 = acc2_q[19] ? (~acc2_q + 1'b1) : acc2_q;

    always @(posedge aclk) begin
        if (!aresetn) begin
            vD_q<=1'b0; mag_q<=21'd0; kD_q<=4'd0;
            rowD_q<=16'd0; ccD_q<={CW{1'b0}};
        end else if (ce) begin
            vD_q   <= v1_q;
            if (!mC_q)      mag_q <= {1'b0,a1} + {1'b0,a2};           // dual magnitude
            else if (!sC_q) mag_q <= {1'b0,a1};                       // single, rectified
            else            mag_q <= acc1_q[19] ? 21'd0 : {1'b0,acc1_q[19:0]}; // single, signed
            kD_q   <= kC_q;
            rowD_q <= row1_q;
            ccD_q  <= cc1_q;
        end
    end

    // ---------------- output stage: shift, clamp -------------------------
    wire [20:0] shv = mag_q >> kD_q;
    wire [7:0]  yv  = (|shv[20:8]) ? 8'hFF : shv[7:0];

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid<=1'b0; m_axis_tdata<=8'd0;
            m_axis_tuser<=1'b0; m_axis_tlast<=1'b0; sofp_q<=1'b1;
        end else if (ce) begin
            m_axis_tvalid <= vD_q;
            if (vD_q) begin
                m_axis_tdata <= yv;
                m_axis_tuser <= sofp_q;
                m_axis_tlast <= (ccD_q == W-1);
                if (sofp_q) sofp_q <= 1'b0;
                if (ccD_q == W-1 && rowD_q == H-1) sofp_q <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
