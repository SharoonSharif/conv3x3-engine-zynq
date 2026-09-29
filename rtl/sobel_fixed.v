// ---------------------------------------------------------------------------
// sobel_fixed.v — hardwired Sobel |Gx|+|Gy| core (k = 3), reconstructed.
// Identical streaming semantics and border policy to conv3x3_engine.v
// (edge-replicated 3x3 window via the same vertical-triple push pipeline),
// with the MAC arrays replaced by constant shift-add arithmetic and no
// AXI4-Lite interface. Reference lean core for the Table 9 comparison.
//   gx = (p2 + 2*p5 + p8) - (p0 + 2*p3 + p6)
//   gy = (p6 + 2*p7 + p8) - (p0 + 2*p1 + p2)
//   y  = clamp((|gx| + |gy|) >> 3, 0, 255)
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module sobel_fixed #(
    parameter integer W  = 160,
    parameter integer H  = 120,
    parameter integer CW = 9
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tuser,
    output reg         m_axis_tlast
);
    localparam ST_ROW    = 2'd0;
    localparam ST_RFLUSH = 2'd1;
    localparam ST_BROW   = 2'd2;
    localparam ST_BFLUSH = 2'd3;

    reg [1:0]    state;
    reg [CW-1:0] col_in, pcnt, col_ff;
    reg [15:0]   row_in, row_out;

    wire stall = m_axis_tvalid && !m_axis_tready;
    wire ce    = !stall;
    assign s_axis_tready = (state == ST_ROW) && ce;
    wire in_hs = s_axis_tvalid && s_axis_tready;

    reg [7:0] lb1 [0:(1<<CW)-1];
    reg [7:0] lb2 [0:(1<<CW)-1];

    reg [7:0] top_px, mid_px, bot_px;
    reg [7:0] t0_t,t0_m,t0_b, t1_t,t1_m,t1_b, t2_t,t2_m,t2_b;

    always @(*) begin
        case (state)
            ST_ROW: begin
                bot_px = s_axis_tdata;
                mid_px = lb1[col_in];
                top_px = (row_in == 16'd1) ? lb1[col_in] : lb2[col_in];
            end
            ST_BROW: begin
                bot_px = lb1[col_ff];
                mid_px = lb1[col_ff];
                top_px = (H >= 2) ? lb2[col_ff] : lb1[col_ff];
            end
            default: begin
                bot_px = t2_b; mid_px = t2_m; top_px = t2_t;
            end
        endcase
    end

    wire push = ce && ( (state==ST_ROW    && in_hs && row_in >= 16'd1) ||
                        (state==ST_RFLUSH) || (state==ST_BROW) || (state==ST_BFLUSH) );

    always @(posedge aclk) begin
        if (!aresetn) begin
            state<=ST_ROW; col_in<={CW{1'b0}}; row_in<=16'd0; pcnt<={CW{1'b0}};
            row_out<=16'd0; col_ff<={CW{1'b0}};
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
                    row_in<=16'd0; row_out<=16'd0; pcnt<={CW{1'b0}};
                end
                lb2[col_in] <= lb1[col_in];
                lb1[col_in] <= s_axis_tdata;
                if (s_axis_tlast) begin
                    col_in <= {CW{1'b0}};
                    if (row_in >= 16'd1) state <= ST_RFLUSH;
                    row_in <= (s_axis_tuser ? 16'd0 : row_in) + 16'd1;
                end else begin
                    col_in <= col_in + 1'b1;
                    if (s_axis_tuser) row_in <= 16'd0;
                end
            end
            ST_RFLUSH: begin
                if (row_out == H-2 && row_in == H) begin
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
                state<=ST_ROW; pcnt<={CW{1'b0}};
            end
            endcase
        end
    end

    // ---------------- Sobel stage (fires the cycle after each push) --------
    reg               push_q;
    reg [CW-1:0]      pcnt_q;
    reg [15:0]        rowp_q, row1_q;
    reg               v1_q;
    reg [CW-1:0]      cc1_q;
    reg signed [12:0] gx_q, gy_q;
    reg               sofp_q;

    wire lrep = (pcnt_q == 2);
    wire [7:0] p0 = lrep ? t1_t : t0_t,  p1 = t1_t,  p2 = t2_t;
    wire [7:0] p3 = lrep ? t1_m : t0_m,  p4 = t1_m,  p5 = t2_m;
    wire [7:0] p6 = lrep ? t1_b : t0_b,  p7 = t1_b,  p8 = t2_b;

    wire [10:0] gx_pos = {3'd0,p2} + {2'd0,p5,1'b0} + {3'd0,p8};
    wire [10:0] gx_neg = {3'd0,p0} + {2'd0,p3,1'b0} + {3'd0,p6};
    wire [10:0] gy_pos = {3'd0,p6} + {2'd0,p7,1'b0} + {3'd0,p8};
    wire [10:0] gy_neg = {3'd0,p0} + {2'd0,p1,1'b0} + {3'd0,p2};

    always @(posedge aclk) begin
        if (!aresetn) begin
            push_q<=1'b0; pcnt_q<={CW{1'b0}}; rowp_q<=16'd0;
            v1_q<=1'b0; row1_q<=16'd0; cc1_q<={CW{1'b0}};
            gx_q<=13'sd0; gy_q<=13'sd0;
        end else if (ce) begin
            push_q <= push;
            if (push) begin
                pcnt_q <= pcnt + 1'b1;
                rowp_q <= row_out;
            end
            v1_q <= push_q && (pcnt_q >= 2);
            if (push_q) begin
                gx_q   <= $signed({2'b00,gx_pos}) - $signed({2'b00,gx_neg});
                gy_q   <= $signed({2'b00,gy_pos}) - $signed({2'b00,gy_neg});
                row1_q <= rowp_q;
                cc1_q  <= pcnt_q - 2'd2;
            end
        end
    end

    wire [11:0] ax  = gx_q[12] ? (~gx_q[11:0] + 1'b1) : gx_q[11:0];
    wire [11:0] ay  = gy_q[12] ? (~gy_q[11:0] + 1'b1) : gy_q[11:0];
    wire [12:0] mag = {1'b0,ax} + {1'b0,ay};
    wire [12:0] shv = mag >> 3;
    wire [7:0]  yv  = (|shv[12:8]) ? 8'hFF : shv[7:0];

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid<=1'b0; m_axis_tdata<=8'd0;
            m_axis_tuser<=1'b0; m_axis_tlast<=1'b0; sofp_q<=1'b1;
        end else if (ce) begin
            m_axis_tvalid <= v1_q;
            if (v1_q) begin
                m_axis_tdata <= yv;
                m_axis_tuser <= sofp_q;
                m_axis_tlast <= (cc1_q == W-1);
                if (sofp_q) sofp_q <= 1'b0;
                if (cc1_q == W-1 && row1_q == H-1) sofp_q <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
