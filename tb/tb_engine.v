// ---------------------------------------------------------------------------
// tb_engine.v — self-checking testbench for conv3x3_engine.
// Frame 1 runs the reset configuration (Sobel, dual, k=3) and is compared
// bit-for-bit against exp_sobel.hex. The kernel is then reprogrammed over
// AXI4-Lite (+CFG=<cfg_*.hex>), the programming latency in clock cycles is
// measured, STATUS.pending is checked, and frame 2 is compared against
// +EXP2=<exp_*.hex>. Random input gaps and output backpressure throughout.
//
//   iverilog -g2012 -o eng.vvp rtl/conv3x3_engine.v tb/tb_engine.v
//   vvp eng.vvp +CFG=tb/vectors/cfg_scharr.hex +EXP2=tb/vectors/exp_scharr.hex
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_engine;
    localparam integer W = 160;
    localparam integer H = 120;
    localparam integer N = W * H;

    reg aclk = 0;  always #5 aclk = ~aclk;      // 100 MHz sim clock
    reg aresetn = 0;
    reg [31:0] cyc = 0;  always @(posedge aclk) cyc <= cyc + 1;

    // DUT wiring
    reg  [7:0] s_tdata = 0;  reg s_tvalid = 0, s_tuser = 0, s_tlast = 0;
    wire       s_tready;
    wire [7:0] m_tdata;      wire m_tvalid, m_tuser, m_tlast;
    reg        m_tready = 1;

    reg  [7:0]  awaddr = 0;  reg awvalid = 0;  wire awready;
    reg  [31:0] wdata = 0;   reg wvalid = 0;   wire wready;
    wire [1:0]  bresp;       wire bvalid;      reg bready = 1;
    reg  [7:0]  araddr = 0;  reg arvalid = 0;  wire arready;
    wire [31:0] rdata;       wire [1:0] rresp; wire rvalid; reg rready = 1;

    conv3x3_engine #(.W(W), .H(H)) dut (
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

    // vectors
    reg [7:0] img  [0:N-1];
    reg [7:0] exp1 [0:N-1];
    reg [7:0] exp2 [0:N-1];
    reg [7:0] cfg  [0:19];
    reg [8*256:1] fn;

    // output capture
    integer oidx = 0, tl_cnt = 0, tu_err = 0, tl_err = 0;
    reg [7:0] got [0:N-1];
    always @(posedge aclk) begin
        if (m_tvalid && m_tready) begin
            got[oidx % N] <= m_tdata;
            if ((oidx % N) == 0 && !m_tuser) tu_err = tu_err + 1;
            if ((oidx % N) != 0 &&  m_tuser) tu_err = tu_err + 1;
            if (m_tlast) tl_cnt = tl_cnt + 1;
            if (m_tlast !== (((oidx % N) % W) == W-1)) tl_err = tl_err + 1;
            oidx = oidx + 1;
        end
    end
    // random backpressure (~80% ready)
    reg [15:0] blfsr = 16'hACE1;
    always @(negedge aclk) begin
        blfsr <= {blfsr[14:0], blfsr[15]^blfsr[13]^blfsr[12]^blfsr[10]};
        m_tready <= (blfsr[2:0] != 3'd0);
    end

    // input driver with random gaps (~75% offered)
    reg [15:0] glfsr = 16'h1D2C;
    task send_pixel(input [7:0] d, input u, input l);
    begin
        @(negedge aclk);
        while (glfsr[1:0] == 2'b00) begin
            glfsr = {glfsr[14:0], glfsr[15]^glfsr[13]^glfsr[12]^glfsr[10]};
            @(negedge aclk);
        end
        glfsr = {glfsr[14:0], glfsr[15]^glfsr[13]^glfsr[12]^glfsr[10]};
        s_tdata = d; s_tuser = u; s_tlast = l; s_tvalid = 1;
        @(posedge aclk);
        while (!s_tready) @(posedge aclk);
        @(negedge aclk);
        s_tvalid = 0; s_tuser = 0; s_tlast = 0;
    end
    endtask

    task send_frame;
        integer r, c;
    begin
        for (r = 0; r < H; r = r + 1)
            for (c = 0; c < W; c = c + 1)
                send_pixel(img[r*W + c], (r == 0 && c == 0), (c == W-1));
    end
    endtask

    // AXI4-Lite master
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

    integer i, err1 = 0, err2 = 0;
    integer c0, c1;
    reg [31:0] stat;
    reg [31:0] timeout = 0;
    always @(posedge aclk) begin
        timeout <= timeout + 1;
        if (timeout > 32'd4_000_000) begin
            $display("TB TIMEOUT: oidx=%0d", oidx);
            $fatal(1);
        end
    end

    initial begin
        if (!$value$plusargs("CFG=%s",  fn)) begin $display("need +CFG=");  $fatal(1); end
        $readmemh(fn, cfg);
        if (!$value$plusargs("EXP2=%s", fn)) begin $display("need +EXP2="); $fatal(1); end
        $readmemh(fn, exp2);
        $readmemh("tb/vectors/image.hex", img);
        $readmemh("tb/vectors/exp_sobel.hex", exp1);

        repeat (8) @(negedge aclk);
        aresetn = 1;
        repeat (4) @(negedge aclk);

        // ---- frame 1: reset configuration (Sobel dual k=3) ----
        send_frame;
        wait (oidx == N);
        repeat (2) @(negedge aclk);   // let the final capture settle
        for (i = 0; i < N; i = i + 1)
            if (got[i] !== exp1[i]) begin
                if (err1 < 5) $display("F1 mismatch @%0d: got %02x exp %02x", i, got[i], exp1[i]);
                err1 = err1 + 1;
            end
        $display("frame1 (reset Sobel): %0d mismatches / %0d px", err1, N);

        // ---- program the new kernel over AXI4-Lite ----
        c0 = cyc;
        axil_wr(8'h00, {24'd0, cfg[1][3:0], 2'b00, cfg[0][0], 1'b1}); // CTRL: EN, MODE, K[7:4]
        for (i = 0; i < 9; i = i + 1) axil_wr(8'h08 + 4*i, {24'd0, cfg[2 + i]});
        for (i = 0; i < 9; i = i + 1) axil_wr(8'h2C + 4*i, {24'd0, cfg[11 + i]});
        c1 = cyc;
        axil_rd(8'h04, stat);
        if (stat[1] !== 1'b1) begin $display("STATUS.pending not set after programming"); err2 = err2 + 1; end
        $display("coefficient-swap programming: %0d clock cycles (19 AXI4-Lite writes)", c1 - c0);

        // ---- frame 2: swapped kernel commits at SOF ----
        send_frame;
        wait (oidx == 2*N);
        repeat (2) @(negedge aclk);
        axil_rd(8'h04, stat);
        if (stat[1] !== 1'b0) begin $display("STATUS.pending not cleared after SOF commit"); err2 = err2 + 1; end
        for (i = 0; i < N; i = i + 1)
            if (got[i] !== exp2[i]) begin
                if (err2 < 5) $display("F2 mismatch @%0d: got %02x exp %02x", i, got[i], exp2[i]);
                err2 = err2 + 1;
            end
        $display("frame2 (swapped kernel): %0d mismatches / %0d px", err2 > 2 ? err2 - 2 : err2, N);

        if (tu_err + tl_err > 0)
            $display("protocol: %0d TUSER errors, %0d TLAST errors", tu_err, tl_err);
        if (err1 + err2 + tu_err + tl_err == 0) begin
            $display("TB PASS: both frames bit-exact; tlast count = %0d (exp %0d)", tl_cnt, 2*H);
            $finish;
        end else begin
            $display("TB FAIL");
            $fatal(1);
        end
    end
endmodule
