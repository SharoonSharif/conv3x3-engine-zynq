// ---------------------------------------------------------------------------
// tb_engine_ext.v — extended self-checking testbench for conv3x3_engine.
// Adds to tb_engine.v: arbitrary frame size, a proper AXI4-Stream source that
// can hold TVALID back-to-back, mid-frame reprogramming, throughput and
// latency measurement, long multi-frame runs and adversarial stalls.
//
// Compile-time frame size (defaults 160 x 120, CW 9):
//   xvlog -sv -d TB_W=1920 -d TB_H=16 -d TB_CW=11 rtl/conv3x3_engine.v tb/tb_engine_ext.v
// Plusargs (2-frame mode, unchanged):
//   +VEC=<dir>        vector directory (image.hex, exp_sobel.hex, cfg/exp_*)
//   +CASE=<name>      kernel programmed for frame 2 (cfg_<name>/exp_<name>)
//   +FULLRATE         source offers a pixel every cycle, sink always ready
//                     (otherwise: random TVALID gaps ~25%, random TREADY ~87%)
//   +MIDFRAME         program the new kernel while frame 1 is still streaming
//                     (at input row H/2); frame 1 must remain pure Sobel
//   +ENPAUSE          clear CTRL.EN mid-frame for 300 cycles (no input may be
//                     accepted), then set it again; frame 1 must stay bit-exact
// Plusargs (long-run mode, selected by +FRAMES):
//   +FRAMES=N         stream N frames of the same image back to back. Frame 1
//                     uses the reset Sobel configuration; frames 2..N cycle
//                     through scharr, prewitt, gaussian, laplacian, sharpen,
//                     sobel (only the cfg_*/exp_* files of the +VEC directory
//                     that the run needs are loaded). The kernel of frame f+1
//                     is written (19 AXI4-Lite writes) while frame f streams,
//                     at an LFSR-chosen input row (row 0 and row H-1 each with
//                     probability 1/8, otherwise uniform). Every frame is
//                     compared against the expected image of its own kernel.
//                     +CASE is ignored in this mode.
//   +NOSWAP           long-run mode without any kernel write (all frames Sobel)
//   +VERBOSE          one line per adversarial stall / input gap event
//   +ADVERSARIAL      around every commit point hold m_axis_tready low for an
//                     LFSR-chosen 1000..2000 cycles. Per frame the LFSR picks
//                     (A) hold the SOF beat until the engine is idle, then
//                     present it with TREADY already low: the stall starts in
//                     the very cycle the SOF beat is accepted (TREADY cannot
//                     gate the acceptance when no output beat is pending), or
//                     (B) present the SOF back to back behind the previous
//                     frame: it is accepted while the previous frame's tail is
//                     still in the pipe and the stall starts in the cycle
//                     right after the accept edge. Another stretch starts at
//                     the first EOL of the frame in the same way (normally in
//                     its accept cycle, since row 0 produces no output). Plus
//                     2..4 input gaps (TVALID low) of 500..1499 cycles per
//                     frame at LFSR-chosen mid-line pixels. The usual random
//                     backpressure / input gaps apply elsewhere. Kernel writes
//                     may land inside a stall (row-0 writes always do).
// Reports: latency from the first accepted input beat to the first output
// beat of frame 1 (cycles and us at 148.5 MHz), cycles per frame (first input
// beat .. last output beat), pixels checked, mismatches, kernel swaps, stall
// statistics. Protocol checks (TUSER on the first pixel only, TLAST on the
// last column) stay active across all frames. Never prints per cycle.
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
    localparam integer MAXF = 4096;     // frame bookkeeping arrays
    localparam integer IDLE_LIMIT = 200000;   // watchdog: cycles without any handshake

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

    // ---------------- vectors ----------------
    // Expected images live in six "slots". Long-run mode: slot j holds the
    // j-th kernel of the rotation (0 scharr, 1 prewitt, 2 gaussian,
    // 3 laplacian, 4 sharpen, 5 sobel); only the slots a run needs are loaded.
    // 2-frame mode: slot 5 = sobel (frame 1), slot 0 = +CASE (frame 2).
    reg [7:0] img   [0:N-1];
    reg [7:0] expk0 [0:N-1];  reg [7:0] expk1 [0:N-1];  reg [7:0] expk2 [0:N-1];
    reg [7:0] expk3 [0:N-1];  reg [7:0] expk4 [0:N-1];  reg [7:0] expk5 [0:N-1];
    reg [7:0] cfg   [0:19];           // kernel being programmed
    reg [7:0] cfgk  [0:6*20-1];       // all six cfg files (slot*20 + i)
    reg [8*256:1] vec, cname, fn;
    reg [8*16:1]  sname [0:5];
    reg fullrate, midframe, enpause, longrun, adversarial, noswap, verbose;
    integer nframes = 2, nload = 0, f, k, r;

    function [8*16:1] rot_name(input integer j);
        case (j)
            0: rot_name = "scharr";    1: rot_name = "prewitt";  2: rot_name = "gaussian";
            3: rot_name = "laplacian"; 4: rot_name = "sharpen";  default: rot_name = "sobel";
        endcase
    endfunction
    function [7:0] exp_px(input integer slot, input integer idx);
        case (slot)
            0: exp_px = expk0[idx];  1: exp_px = expk1[idx];  2: exp_px = expk2[idx];
            3: exp_px = expk3[idx];  4: exp_px = expk4[idx];  default: exp_px = expk5[idx];
        endcase
    endfunction
    // expected-image slot of 0-based frame fi
    function integer fslot(input integer fi);
        if (fi == 0 || noswap) fslot = 5;
        else if (!longrun)     fslot = 0;
        else                   fslot = (fi - 1) % 6;
    endfunction
    task load_slot(input integer slot, input [8*16:1] name);
    begin
        $sformat(fn, "%0s/exp_%0s.hex", vec, name);
        case (slot)
            0: $readmemh(fn, expk0);  1: $readmemh(fn, expk1);  2: $readmemh(fn, expk2);
            3: $readmemh(fn, expk3);  4: $readmemh(fn, expk4);  default: $readmemh(fn, expk5);
        endcase
        sname[slot] = name;
        nload = nload + 1;
    end
    endtask

    // ---------------- output capture + protocol checks ----------------
    integer oidx = 0, tl_cnt = 0, tu_err = 0, tl_err = 0, err_tot = 0, ovf_err = 0;
    integer err_f [0:MAXF-1];
    integer t_fin [0:MAXF-1];         // cycle of the first accepted input beat per frame
    integer t_lout [0:MAXF-1];        // cycle of the last output beat per frame
    integer t_first_out = -1, ofr, opx;
    reg [7:0] ev;
    always @(posedge aclk) begin
        if (m_tvalid && m_tready) begin
            if (oidx < nframes * N) begin
                ofr = oidx / N;  opx = oidx % N;
                ev  = exp_px(fslot(ofr), opx);
                if (m_tdata !== ev) begin
                    if (err_tot < 10) $display("F%0d (%0s) mismatch @%0d (r%0d c%0d): got %02x exp %02x",
                                               ofr + 1, sname[fslot(ofr)], opx, opx / W, opx % W, m_tdata, ev);
                    err_f[ofr] = err_f[ofr] + 1;  err_tot = err_tot + 1;
                end
                if (opx == 0 && !m_tuser) tu_err = tu_err + 1;
                if (opx != 0 &&  m_tuser) tu_err = tu_err + 1;
                if (m_tlast) tl_cnt = tl_cnt + 1;
                if (m_tlast !== ((opx % W) == W-1)) tl_err = tl_err + 1;
                if (oidx == 0)   t_first_out = cyc;
                if (opx == N-1)  t_lout[ofr] = cyc;
            end else begin
                if (ovf_err < 5) $display("extra output beat after the last frame (oidx %0d)", oidx);
                ovf_err = ovf_err + 1;
            end
            oidx = oidx + 1;
        end
    end

    // ---------------- AXI4-Stream source + sink (one negedge driver) ------
    // Source: a beat is presented, held until accepted, and the next beat
    // follows in the very next cycle unless a random gap is drawn (never in
    // +FULLRATE) or an adversarial long gap is due.
    // Sink: random TREADY (~87%), always ready in +FULLRATE, long stalls in
    // +ADVERSARIAL. Both live in one block so the sink sees the beat the
    // source presents in the same cycle.
    reg [15:0] blfsr = 16'hACE1, glfsr = 16'h1D2C, alfsr = 16'h7A3B, plfsr = 16'h5EED;
    function [15:0] lfsr_next(input [15:0] x);
        lfsr_next = {x[14:0], x[15]^x[13]^x[12]^x[10]};
    endfunction
    integer iidx = 0, stall_in = 0, src_frame_end = 0;
    reg     src_run = 0, acc = 0;
    reg     sof_hs = 0, eol1_hs = 0, pre_armed = 0;
    integer stall_left = 0, gap_left = 0, stall_new = 0;
    integer gap_t [0:3];  reg [3:0] gap_srv = 4'b0;  integer ngap_t = 0, gi, gk;
    integer n_stall = 0, n_gap = 0, n_swap = 0, sof_lo = 0, eol_lo = 0, sof_held = 0;
    reg     frame_drawn = 0, sof_hold = 0;
    integer stall_lmin = 0, stall_lmax = 0, gap_lmax = 0, slen;
    integer lo_run = 0, lo_max = 0, pend_run = 0, pend_max = 0;

    // posedge: sample the handshake (s_tready is combinational from DUT
    // registers and m_tready, so this reads the pre-edge value)
    always @(posedge aclk) begin
        if (s_tvalid && !s_tready) stall_in = stall_in + 1;
        if (s_tvalid && s_tready) begin
            if ((iidx % N) == 0) begin
                t_fin[iidx / N] = cyc;  sof_hs = 1;  frame_drawn = 0;
                if (!m_tready) sof_lo = sof_lo + 1;
            end
            if (s_tlast && (iidx % N) < W) begin
                eol1_hs = 1;
                if (!m_tready) eol_lo = eol_lo + 1;
            end
            iidx = iidx + 1;  acc = 1;  pre_armed = 0;
        end
        if (!m_tready) begin lo_run = lo_run + 1; if (lo_run > lo_max) lo_max = lo_run; end
        else lo_run = 0;
        if (m_tvalid && !m_tready) begin pend_run = pend_run + 1; if (pend_run > pend_max) pend_max = pend_run; end
        else pend_run = 0;
    end

    always @(negedge aclk) begin
        // ---- source ----
        glfsr = lfsr_next(glfsr);
        if (!s_tvalid || acc) begin
            acc = 0;
            s_tvalid = 0; s_tuser = 0; s_tlast = 0;
            if (gap_left > 0) begin
                gap_left = gap_left - 1;                       // adversarial long gap
            end else if (src_run && iidx < src_frame_end && (fullrate || glfsr[1:0] != 2'b00)) begin
                if (adversarial && (iidx % N) == 0 && !frame_drawn) begin   // new frame:
                    alfsr = lfsr_next(alfsr);  ngap_t = 2 + (alfsr % 3);  gap_srv = 4'b0;
                    for (gi = 0; gi < 4; gi = gi + 1) begin               // draw gap points
                        alfsr = lfsr_next(alfsr);  gap_t[gi] = (alfsr % H) * W;
                        alfsr = lfsr_next(alfsr);  gap_t[gi] = gap_t[gi] + 1 + (alfsr % (W - 2));
                    end
                    alfsr = lfsr_next(alfsr);                             // and the SOF variant:
                    sof_hold = (iidx != 0) && alfsr[0];                   // hold SOF until idle,
                    if (sof_hold) sof_held = sof_held + 1;                // or back-to-back
                    frame_drawn = 1;
                end
                gi = -1;
                if (adversarial)
                    for (gk = 0; gk < ngap_t; gk = gk + 1)
                        if (!gap_srv[gk] && gap_t[gk] == (iidx % N)) gi = gk;
                if (adversarial && (iidx % N) == 0 && sof_hold && !(s_tready && !m_tvalid)) begin
                    // variant A: present the SOF only once the engine is idle, so that the
                    // stall below starts in the very cycle the SOF beat is accepted
                end else if (gi >= 0) begin
                    gap_srv[gi] = 1'b1;  alfsr = lfsr_next(alfsr);
                    gap_left = 500 + (alfsr % 1000);  n_gap = n_gap + 1;
                    if (gap_left > gap_lmax) gap_lmax = gap_left;
                    if (verbose) $display("  [cyc %0d] input gap: %0d cycles before pixel %0d (r%0d c%0d) of frame %0d",
                                          cyc, gap_left, iidx % N, (iidx % N) / W, (iidx % N) % W, iidx / N + 1);
                end else begin
                    s_tdata  = img[iidx % N];
                    s_tuser  = ((iidx % N) == 0);
                    s_tlast  = (((iidx % N) % W) == W-1);
                    s_tvalid = 1;
                end
            end
        end
        // ---- sink (the random TREADY sequence is the same as before the
        //      long-run extension: the LFSR is used, then advanced) ----
        if (adversarial) begin
            stall_new = 0;
            if (sof_hs || eol1_hs) begin                       // commit point passed
                stall_new = sof_hs ? 1 : 2;  sof_hs = 0; eol1_hs = 0;
            end else if (s_tvalid && s_tready && !m_tvalid && !pre_armed && stall_left == 0 &&
                         (s_tuser || (s_tlast && (iidx % N) < W))) begin
                pre_armed = 1;  stall_new = s_tuser ? 3 : 4;   // beat is accepted at the next
            end                                                //  edge whatever TREADY: stall now
            if (stall_new != 0) begin
                alfsr = lfsr_next(alfsr);  slen = 1000 + (alfsr % 1001);
                if (verbose) $display("  [cyc %0d] stall %0s %0s: %0d cycles (%0s%0d left), pixel %0d of frame %0d, m_tvalid=%0d",
                                      cyc, (stall_new == 1 || stall_new == 3) ? "SOF" : "EOL",
                                      (stall_new <= 2) ? "after accept" : "in accept cycle", slen,
                                      (stall_left == 0) ? "new" : "extends ", stall_left, iidx % N, iidx / N + 1, m_tvalid);
                if (stall_left == 0) n_stall = n_stall + 1;
                if (slen > stall_left) stall_left = slen;      // start or extend
                if (stall_lmin == 0 || slen < stall_lmin) stall_lmin = slen;
                if (slen > stall_lmax) stall_lmax = slen;
            end
            if (stall_left > 0) begin m_tready = 0;  stall_left = stall_left - 1; end
            else m_tready = (blfsr[2:0] != 3'd0);
        end else begin
            m_tready = fullrate ? 1'b1 : (blfsr[2:0] != 3'd0);
        end
        blfsr = lfsr_next(blfsr);
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
        n_swap = n_swap + 1;
        axil_rd(8'h04, stat);
        if (stat[1] !== 1'b1) begin $display("STATUS.pending not set after programming"); perr = perr + 1; end
    end
    endtask

    // ---------------- watchdog: no handshake for IDLE_LIMIT cycles ---------
    reg [31:0] idle = 0;
    always @(posedge aclk) begin
        if ((s_tvalid && s_tready) || (m_tvalid && m_tready)) idle <= 0;
        else idle <= idle + 1;
        if (idle > IDLE_LIMIT) begin
            $display("TB TIMEOUT: no handshake for %0d cycles (iidx=%0d oidx=%0d)", IDLE_LIMIT, iidx, oidx);
            $fatal(1); $finish;
        end
    end

    integer lat, cpf, cpf_min, cpf_max, swap_stalled;
    real    cpf_sum;
    initial begin
        fullrate    = $test$plusargs("FULLRATE");
        midframe    = $test$plusargs("MIDFRAME");
        enpause     = $test$plusargs("ENPAUSE");
        adversarial = $test$plusargs("ADVERSARIAL");
        noswap      = $test$plusargs("NOSWAP");
        verbose     = $test$plusargs("VERBOSE");
        longrun     = $value$plusargs("FRAMES=%d", nframes);
        if (!longrun) nframes = 2;
        if (nframes < 1 || nframes > MAXF) begin
            $display("FRAMES must be 1..%0d", MAXF); $fatal(1); $finish;
        end
        for (f = 0; f < MAXF; f = f + 1) begin err_f[f] = 0; t_fin[f] = -1; t_lout[f] = -1; end
        if (!$value$plusargs("VEC=%s", vec))    vec   = "tb/vectors";
        if (!$value$plusargs("CASE=%s", cname)) cname = "scharr";
        $sformat(fn, "%0s/image.hex", vec);  $readmemh(fn, img);
        for (f = 0; f < 6; f = f + 1) sname[f] = rot_name(f);
        if (longrun) begin
            // slots actually used: sobel (frame 1) + the first min(N-1, 5) of the rotation
            load_slot(5, "sobel");
            if (!noswap)
                for (f = 0; f < 5 && f < nframes - 1; f = f + 1) load_slot(f, rot_name(f));
            for (f = 0; f < 6; f = f + 1) begin
                $sformat(fn, "%0s/cfg_%0s.hex", vec, rot_name(f));  $readmemh(fn, cfg);
                for (i = 0; i < 20; i = i + 1) cfgk[f*20 + i] = cfg[i];
            end
            $display("config: W=%0d H=%0d CW=%0d frames=%0d fullrate=%0d adversarial=%0d noswap=%0d (long-run mode, %0d expected images loaded)",
                     W, H, CW, nframes, fullrate, adversarial, noswap, nload);
        end else begin
            load_slot(5, "sobel");
            load_slot(0, cname);
            $sformat(fn, "%0s/cfg_%0s.hex", vec, cname); $readmemh(fn, cfg);
            $display("config: W=%0d H=%0d CW=%0d case=%0s fullrate=%0d midframe=%0d enpause=%0d adversarial=%0d",
                     W, H, CW, cname, fullrate, midframe, enpause, adversarial);
        end

        repeat (8) @(negedge aclk); aresetn = 1; repeat (4) @(negedge aclk);

        if (longrun) begin
            // -------- long-run mode: N frames back to back --------
            swap_stalled = 0;
            src_frame_end = N; src_run = 1;
            for (f = 1; f <= nframes; f = f + 1) begin
                if (f > 1) begin
                    wait (iidx >= (f-1)*N + 1);                // SOF of frame f accepted
                    repeat (4) @(posedge aclk);
                    axil_rd(8'h04, stat);
                    if (stat[1] !== 1'b0) begin
                        $display("STATUS.pending not cleared after SOF of frame %0d", f); perr = perr + 1;
                    end
                end
                if (f < nframes) begin
                    if (!noswap) begin
                        plfsr = lfsr_next(plfsr);
                        if      (plfsr[2:0] == 3'd0) r = 0;
                        else if (plfsr[2:0] == 3'd1) r = H - 1;
                        else                         r = plfsr % H;
                        wait (iidx >= (f-1)*N + r*W + 1);      // first pixel of row r accepted
                        k = fslot(f);                          // slot of frame f+1 (0-based f)
                        for (i = 0; i < 20; i = i + 1) cfg[i] = cfgk[k*20 + i];
                        program_kernel;
                        if (lo_run > 0) swap_stalled = swap_stalled + 1;
                        $display("swap %0d: %0s for frame %0d written during frame %0d at input row %0d (%0d cycles, 19 writes%0s)",
                                 n_swap, sname[k], f + 1, f, r, c1 - c0, (lo_run > 0) ? ", output stalled" : "");
                    end
                    src_frame_end = (f+1)*N;                   // release the next frame
                end
            end
            wait (oidx == nframes*N);
            repeat (32) @(negedge aclk);
            axil_rd(8'h04, stat);
            if (stat[0] !== 1'b0) begin $display("STATUS.busy still set after the last frame"); perr = perr + 1; end
        end else begin
            // -------- 2-frame mode (unchanged behaviour) --------
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
        end

        // -------- report --------
        lat = t_first_out - t_fin[0];
        $display("latency frame1: first accepted input beat (cyc %0d) to first output beat (cyc %0d) = %0d cycles = %0.3f us at 148.5 MHz",
                 t_fin[0], t_first_out, lat, lat / 148.5);
        if (longrun) begin
            cpf_min = -1; cpf_max = 0; cpf_sum = 0.0;
            for (f = 0; f < nframes; f = f + 1) begin
                cpf = t_lout[f] - t_fin[f];
                $display("frame %0d (%0s): %0d mismatches / %0d px, %0d cycles first-in..last-out (%0.4f cyc/px)",
                         f + 1, sname[fslot(f)], err_f[f], N, cpf, cpf * 1.0 / N);
                if (cpf_min < 0 || cpf < cpf_min) cpf_min = cpf;
                if (cpf > cpf_max) cpf_max = cpf;
                cpf_sum = cpf_sum + cpf;
            end
            $display("cycles/frame: min %0d max %0d mean %0.1f; input stall cycles total %0d",
                     cpf_min, cpf_max, cpf_sum / nframes, stall_in);
            if (adversarial)
                $display("adversarial: %0d long tready stalls (lengths %0d..%0d), longest tready-low stretch %0d cycles (%0d with an output beat pending); SOF held until the engine was idle for %0d frames, back-to-back for %0d; tready low in the accept cycle for %0d of %0d SOF beats and %0d of %0d first-EOL beats; %0d input gaps >= 500 cycles (longest %0d); %0d of %0d kernel writes finished while the output was stalled",
                         n_stall, stall_lmin, stall_lmax, lo_max, pend_max, sof_held, nframes - 1 - sof_held, sof_lo, nframes, eol_lo, nframes, n_gap, gap_lmax, swap_stalled, n_swap);
            $display("summary: %0d frames, %0d pixels checked, %0d mismatches, %0d kernel swaps, tlast count %0d (exp %0d), %0d TUSER errors, %0d TLAST errors, %0d extra beats, %0d register errors",
                     nframes, (oidx < nframes*N) ? oidx : nframes*N, err_tot, n_swap, tl_cnt, nframes*H, tu_err, tl_err, ovf_err, perr);
            if (err_tot + tu_err + tl_err + ovf_err + perr == 0 && oidx == nframes*N && tl_cnt == nframes*H) begin
                $display("TB PASS: all %0d frames bit-exact (%0d px, %0d kernel swaps)", nframes, oidx, n_swap);
                $finish;
            end else begin
                $display("TB FAIL"); $fatal(1); $finish;
            end
        end else begin
            $display("frame1 (Sobel%0s): %0d mismatches / %0d px", midframe ? ", kernel written mid-frame" : "", err_f[0], N);
            $display("frame2 (%0s): %0d mismatches / %0d px", cname, err_f[1], N);
            $display("throughput frame1: %0d cycles first-in..last-out for %0d px (%0.4f cyc/px); input stall cycles total %0d",
                     t_lout[0] - t_fin[0], N, (t_lout[0] - t_fin[0]) * 1.0 / N, stall_in);
            $display("throughput frame2: %0d cycles first-in..last-out (%0.4f cyc/px)",
                     t_lout[1] - t_fin[1], (t_lout[1] - t_fin[1]) * 1.0 / N);
            if (adversarial)
                $display("adversarial: %0d long tready stalls (lengths %0d..%0d), longest tready-low stretch %0d cycles; %0d input gaps >= 500 cycles (longest %0d)",
                         n_stall, stall_lmin, stall_lmax, lo_max, n_gap, gap_lmax);
            if (tu_err + tl_err > 0) $display("protocol: %0d TUSER errors, %0d TLAST errors", tu_err, tl_err);
            if (err_tot + tu_err + tl_err + ovf_err + perr == 0 && oidx == 2*N) begin
                $display("TB PASS: both frames bit-exact; tlast count = %0d (exp %0d)", tl_cnt, 2*H);
                $finish;
            end else begin
                $display("TB FAIL"); $fatal(1); $finish;
            end
        end
    end
endmodule
