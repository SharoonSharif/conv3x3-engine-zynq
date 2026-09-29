// ---------------------------------------------------------------------------
// tb_sobel_fixed.v — single-frame self-checking testbench for sobel_fixed.
// Compares the streamed output bit-for-bit against exp_sobel.hex under
// random input gaps and output backpressure.
//   iverilog -g2012 -o sob.vvp rtl/sobel_fixed.v tb/tb_sobel_fixed.v && vvp sob.vvp
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_sobel_fixed;
    localparam integer W = 160;
    localparam integer H = 120;
    localparam integer N = W * H;

    reg aclk = 0;  always #5 aclk = ~aclk;
    reg aresetn = 0;

    reg  [7:0] s_tdata = 0;  reg s_tvalid = 0, s_tuser = 0, s_tlast = 0;
    wire       s_tready;
    wire [7:0] m_tdata;      wire m_tvalid, m_tuser, m_tlast;
    reg        m_tready = 1;

    sobel_fixed #(.W(W), .H(H)) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tuser(s_tuser), .s_axis_tlast(s_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tuser(m_tuser), .m_axis_tlast(m_tlast));

    reg [7:0] img  [0:N-1];
    reg [7:0] exp1 [0:N-1];
    reg [7:0] got  [0:N-1];

    integer oidx = 0, tl_cnt = 0, tu_err = 0, tl_err = 0;
    always @(posedge aclk) begin
        if (m_tvalid && m_tready) begin
            got[oidx] <= m_tdata;
            if (oidx == 0 && !m_tuser) tu_err = tu_err + 1;
            if (oidx != 0 &&  m_tuser) tu_err = tu_err + 1;
            if (m_tlast) tl_cnt = tl_cnt + 1;
            if (m_tlast !== ((oidx % W) == W-1)) tl_err = tl_err + 1;
            oidx = oidx + 1;
        end
    end

    reg [15:0] blfsr = 16'hACE1;
    always @(negedge aclk) begin
        blfsr <= {blfsr[14:0], blfsr[15]^blfsr[13]^blfsr[12]^blfsr[10]};
        m_tready <= (blfsr[2:0] != 3'd0);
    end

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

    integer r, c, i, errs = 0;
    reg [31:0] timeout = 0;
    always @(posedge aclk) begin
        timeout <= timeout + 1;
        if (timeout > 32'd2_000_000) begin
            $display("TB TIMEOUT: oidx=%0d", oidx);
            $fatal(1);
        end
    end

    initial begin
        $readmemh("tb/vectors/image.hex", img);
        $readmemh("tb/vectors/exp_sobel.hex", exp1);
        repeat (8) @(negedge aclk);
        aresetn = 1;
        repeat (4) @(negedge aclk);

        for (r = 0; r < H; r = r + 1)
            for (c = 0; c < W; c = c + 1)
                send_pixel(img[r*W + c], (r == 0 && c == 0), (c == W-1));

        wait (oidx == N);
        repeat (2) @(negedge aclk);
        for (i = 0; i < N; i = i + 1)
            if (got[i] !== exp1[i]) begin
                if (errs < 5) $display("mismatch @%0d: got %02x exp %02x", i, got[i], exp1[i]);
                errs = errs + 1;
            end
        if (tu_err + tl_err > 0)
            $display("protocol: %0d TUSER errors, %0d TLAST errors", tu_err, tl_err);
        if (errs + tu_err + tl_err == 0) begin
            $display("TB PASS: sobel_fixed bit-exact over %0d px; tlast count = %0d (exp %0d)", N, tl_cnt, H);
            $finish;
        end else begin
            $display("TB FAIL: %0d mismatches", errs);
            $fatal(1);
        end
    end
endmodule
