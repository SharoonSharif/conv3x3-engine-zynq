// ---------------------------------------------------------------------------
// tb_engine_ext.v — extended self-checking testbench for conv3x3_engine.
// Adds to tb_engine.v: arbitrary frame size, a proper AXI4-Stream source that
// can hold TVALID back-to-back, mid-frame reprogramming, and throughput
// measurement.
//
// Compile-time frame size (defaults 160 x 120, CW 9):
//   xvlog -sv -d TB_W=1920 -d TB_H=16 -d TB_CW=11 rtl/conv3x3_engine.v tb/tb_engine_ext.v
// Plusargs:
//   +VEC=<dir>        vector directory (image.hex, exp_sobel.hex, cfg/exp_*)
//   +CASE=<name>      kernel programmed for frame 2 (cfg_<name>/exp_<name>)
//   +FULLRATE         source offers a pixel every cycle, sink always ready
//                     (otherwise: random TVALID gaps ~25%, random TREADY ~80%)
//   +MIDFRAME         program the new kernel while frame 1 is still streaming
//                     (at input row H/2); frame 1 must remain pure Sobel
//   +ENPAUSE          clear CTRL.EN mid-frame for 300 cycles (no input may be
//                     accepted), then set it again; frame 1 must stay bit-exact
// Reports cycles per frame (first input beat to last output beat) and input
// stall cycles (TVALID && !TREADY).
// ---------------------------------------------------------------------------
`timescale 1ns/1ps
`ifndef TB_W
  `define TB_W 160
`endif
`ifndef TB_H
  `define TB_H 120
`endif
`ifndef TB_CW
  `define TB_CW 9
`endif
`ifndef TB_LB_BRAM
  `define TB_LB_BRAM 0      // 1: block-RAM line buffers (LB_BRAM=1)
`endif

module tb_engine_ext;
    localparam integer W  = `TB_W;
    localparam integer H  = `TB_H;
    localparam integer N  = W * H;
    localparam integer CW = `TB_CW;     // 2**CW > W+1 (same as synthesis)

    reg aclk = 0;  always #5 aclk = ~aclk;
    reg aresetn = 0;
    reg [31:0] cyc = 0;  always @(posedge aclk) cyc <= cyc + 1;

    reg  [7:0] s_tdata = 0;  reg s_tvalid = 0, s_tuser = 0, s_tlast = 0;
    wire       s_tready;
    wire [7:0] m_tdata;      wire m_tvalid, m_tuser, m_tlast;
    reg        m_tready = 1;

    reg  [7:0]  awaddr = 0;  reg awvalid = 0;  wire awready;
    reg  [31:0] wdata = 0;   reg wvalid = 0;   wire wready;
    wire [1:0]  bresp;       wire bvalid;      reg bready = 1;
    reg  [7:0]  araddr = 0;  reg arvalid = 0;  wire arready;
    wire [31:0] rdata;       wire [1:0] rresp; wire rvalid; reg rready = 1;

    conv3x3_engine #(.W(W), .H(H), .CW(CW), .LB_BRAM(`TB_LB_BRAM)) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tuser(s_tuser), .s_axis_tlast(s_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tuser(m_tuser), .m_axis_tlast(m_tlast),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid),
        .s_axil_rready(rready));

    reg [7:0] img  [0:N-1];
    reg [7:0] exp1 [0:N-1];
    reg [7:0] exp2 [0:N-1];
    reg [7:0] cfg  [0:19];
    reg [8*256:1] vec, cname, fn;
    reg fullrate, midframe, enpause;

    // ---------------- output capture + protocol checks ----------------
    integer oidx = 0, tl_cnt = 0, tu_err = 0, tl_err = 0, err1 = 0, err2 = 0;
    integer t_first_out = -1, t_last_out1 = 0, t_last_out2 = 0;
    always @(posedge aclk) begin
        if (m_tvalid && m_tready) begin
            if (oidx < N) begin
                if (m_tdata !== exp1[oidx]) begin
                    if (err1 < 5) $display("F1 mismatch @%0d (r%0d c%0d): got %02x exp %02x",
                                           oidx, oidx / W, oidx % W, m_tdata, exp1[oidx]);
                    err1 = err1 + 1;
                end
            end else if (oidx < 2*N) begin
                if (m_tdata !== exp2[oidx-N]) begin
                    if (err2 < 5) $display("F2 mismatch @%0d (r%0d c%0d): got %02x exp %02x",
                                           oidx-N, (oidx-N) / W, (oidx-N) % W, m_tdata, exp2[oidx-N]);
                    err2 = err2 + 1;
                end
            end
            if ((oidx % N) == 0 && !m_tuser) tu_err = tu_err + 1;
            if ((oidx % N) != 0 &&  m_tuser) tu_err = tu_err + 1;
            if (m_tlast) tl_cnt = tl_cnt + 1;
            if (m_tlast !== (((oidx % N) % W) == W-1)) tl_err = tl_err + 1;
            if (oidx == N-1)   t_last_out1 = cyc;
            if (oidx == 2*N-1) t_last_out2 = cyc;
            oidx = oidx + 1;
        end
    end

    // ---------------- sink backpressure ----------------
    reg [15:0] blfsr = 16'hACE1;
    always @(negedge aclk) begin
        blfsr <= {blfsr[14:0], blfsr[15]^blfsr[13]^blfsr[12]^blfsr[10]};
        m_tready <= fullrate ? 1'b1 : (blfsr[2:0] != 3'd0);
    end

    // ---------------- AXI4-Stream source (TVALID may stay high) ----------
    // A beat is presented, held until accepted, and the next beat follows in
    // the very next cycle unless a random gap is drawn (never in +FULLRATE).
    reg [15:0] glfsr = 16'h1D2C;
    integer iidx = 0, stall_in = 0, t_first_in1 = -1, t_first_in2 = -1;
    reg     src_run = 0, acc = 0;
    integer src_frame_end = 0;
    // posedge: sample the handshake (s_tready is combinational from DUT
    // registers, so this reads the pre-edge value)
    always @(posedge aclk) begin
        if (s_tvalid && !s_tready) stall_in = stall_in + 1;
        if (s_tvalid && s_tready) begin
            if (iidx == 0) t_first_in1 = cyc;
            if (iidx == N) t_first_in2 = cyc;
            iidx = iidx + 1;
            acc  = 1;
        end
    end
    // negedge: hold a pending beat unchanged; otherwise present the next beat
    // (back-to-back in +FULLRATE) or idle for a random gap
    always @(negedge aclk) begin
        glfsr = {glfsr[14:0], glfsr[15]^glfsr[13]^glfsr[12]^glfsr[10]};
        if (!s_tvalid || acc) begin
            acc = 0;
            if (src_run && iidx < src_frame_end && (fullrate || glfsr[1:0] != 2'b00)) begin
                s_tdata  = img[iidx % N];
                s_tuser  = ((iidx % N) == 0);
                s_tlast  = (((iidx % N) % W) == W-1);
                s_tvalid = 1;
            end else begin
                s_tvalid = 0; s_tuser = 0; s_tlast = 0;
            end
        end
    end

    // ---------------- AXI4-Lite master ----------------
    task axil_wr(input [7:0] a, input [31:0] d);
    begin
        @(negedge aclk); awaddr = a; awvalid = 1; wdata = d; wvalid = 1;
        fork
            begin @(posedge aclk); while (!awready) @(posedge aclk);
                  @(negedge aclk); awvalid = 0; end
            begin @(posedge aclk); while (!wready)  @(posedge aclk);
                  @(negedge aclk); wvalid = 0; end
        join
        @(posedge aclk); while (!bvalid) @(posedge aclk);
    end
    endtask
    task axil_rd(input [7:0] a, output [31:0] d);
    begin
        @(negedge aclk); araddr = a; arvalid = 1;
        @(posedge aclk); while (!arready) @(posedge aclk);
        @(negedge aclk); arvalid = 0;
        @(posedge aclk); while (!rvalid) @(posedge aclk);
        d = rdata;
    end
    endtask
    integer i, c0, c1, perr = 0, pause_i0 = 0;
    reg [31:0] stat;
    task program_kernel;
    begin
        c0 = cyc;
        axil_wr(8'h00, {24'd0, cfg[1][3:0], 1'b0, cfg[0][1], cfg[0][0], 1'b1});
        for (i = 0; i < 9; i = i + 1) axil_wr(8'h08 + 4*i, {24'd0, cfg[2 + i]});
        for (i = 0; i < 9; i = i + 1) axil_wr(8'h2C + 4*i, {24'd0, cfg[11 + i]});
        c1 = cyc;
        axil_rd(8'h04, stat);
        if (stat[1] !== 1'b1) begin $display("STATUS.pending not set after programming"); perr = perr + 1; end
    end
    endtask

    reg [63:0] timeout = 0;
    always @(posedge aclk) begin
        timeout <= timeout + 1;
        if (timeout > 64'd40 * N + 64'd200000) begin
            $display("TB TIMEOUT: iidx=%0d oidx=%0d", iidx, oidx); $fatal(1); $finish;
        end
    end

    initial begin
        fullrate = $test$plusargs("FULLRATE");
        midframe = $test$plusargs("MIDFRAME");
        enpause  = $test$plusargs("ENPAUSE");
        if (!$value$plusargs("VEC=%s", vec))    vec   = "tb/vectors";
        if (!$value$plusargs("CASE=%s", cname)) cname = "scharr";
        $sformat(fn, "%0s/image.hex", vec);          $readmemh(fn, img);
        $sformat(fn, "%0s/exp_sobel.hex", vec);      $readmemh(fn, exp1);
        $sformat(fn, "%0s/cfg_%0s.hex", vec, cname); $readmemh(fn, cfg);
        $sformat(fn, "%0s/exp_%0s.hex", vec, cname); $readmemh(fn, exp2);
        $display("config: W=%0d H=%0d CW=%0d case=%0s fullrate=%0d midframe=%0d enpause=%0d",
                 W, H, CW, cname, fullrate, midframe, enpause);

        repeat (8) @(negedge aclk); aresetn = 1; repeat (4) @(negedge aclk);

        // frame 1
        src_frame_end = N; src_run = 1;
        if (enpause) begin
            // CTRL.EN = 0 mid-frame (reset config otherwise): input must stop at
            // once and stay stopped; EN = 1 resumes; frame 1 must stay bit-exact.
            wait (iidx >= (H/4) * W + W/3);
            axil_wr(8'h00, {24'd0, 4'd3, 4'b0000});
            repeat (4) @(posedge aclk);
            pause_i0 = iidx;
            repeat (300) @(posedge aclk);
            if (iidx != pause_i0) begin
                $display("EN=0 did not pause input: %0d beats accepted", iidx - pause_i0);
                perr = perr + 1;
            end
            axil_wr(8'h00, {24'd0, 4'd3, 4'b0001});
            $display("EN pause: input held for 300 cycles at pixel %0d, then resumed", pause_i0);
        end
        if (midframe) begin
            wait (iidx >= (H/2) * W);
            program_kernel;
            if (iidx >= N) $display("WARNING: programming finished after frame 1 input ended");
        end
        wait (oidx == N);
        if (!midframe) program_kernel;
        $display("coefficient-swap programming: %0d clock cycles (19 AXI4-Lite writes)%0s",
                 c1 - c0, midframe ? " [issued mid-frame]" : "");

        // frame 2
        src_frame_end = 2*N;
        wait (oidx == 2*N);
        repeat (4) @(negedge aclk);
        axil_rd(8'h04, stat);
        if (stat[1] !== 1'b0) begin $display("STATUS.pending not cleared after SOF commit"); perr = perr + 1; end

        $display("frame1 (Sobel%0s): %0d mismatches / %0d px", midframe ? ", kernel written mid-frame" : "", err1, N);
        $display("frame2 (%0s): %0d mismatches / %0d px", cname, err2, N);
        $display("throughput frame1: %0d cycles first-in..last-out for %0d px (%0.4f cyc/px); input stall cycles total %0d",
                 t_last_out1 - t_first_in1, N, (t_last_out1 - t_first_in1) * 1.0 / N, stall_in);
        $display("throughput frame2: %0d cycles first-in..last-out (%0.4f cyc/px)",
                 t_last_out2 - t_first_in2, (t_last_out2 - t_first_in2) * 1.0 / N);
        if (tu_err + tl_err > 0) $display("protocol: %0d TUSER errors, %0d TLAST errors", tu_err, tl_err);
        if (err1 + err2 + tu_err + tl_err + perr == 0) begin
            $display("TB PASS: both frames bit-exact; tlast count = %0d (exp %0d)", tl_cnt, 2*H);
            $finish;
        end else begin
            $display("TB FAIL"); $fatal(1); $finish;
        end
    end
endmodule
