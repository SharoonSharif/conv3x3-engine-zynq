@echo off
rem Long-run and adversarial engine tests (tb/tb_engine_ext.v with +FRAMES,
rem +ADVERSARIAL, +NOSWAP). Run from the repo root with Vivado's bin on PATH,
rem after regenerating the vectors:
rem   python golden/gen_vectors_wide.py 1920 16
rem   python golden/gen_vectors_wide.py 1920 1080
rem Usage: tb\run_xsim_long.bat [all|a|b|c|d|e|f]   (default: all)
rem   a  1920x16    FRAMES=60  ADVERSARIAL   (1.84 Mpx)
rem   b  160x120    FRAMES=120 ADVERSARIAL   (2.30 Mpx)
rem   c  1920x1080  FRAMES=4   FULLRATE      (8.29 Mpx, kernels rotate mid-frame)
rem   d  1920x1080  FRAMES=3   ADVERSARIAL   (6.22 Mpx)
rem   e  1920x1080  FRAMES=2   FULLRATE NOSWAP  (no kernel write at all)
rem   f  1920x1080  FRAMES=2   FULLRATE         (one mid-frame kernel write)
rem Logs land in tb\logs_long\. Every run must print "TB PASS".
setlocal
set SEL=%1
if "%SEL%"=="" set SEL=all
if not exist tb\logs_long mkdir tb\logs_long

call xvlog -sv -d "TB_W=1920" -d "TB_H=16" -d "TB_CW=11" rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s long1920x16 || exit /b 1
call xvlog -sv rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s long160 || exit /b 1
call xvlog -sv -d "TB_W=1920" -d "TB_H=1080" -d "TB_CW=11" rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s long1080p || exit /b 1

if "%SEL%"=="all" goto run_a
if "%SEL%"=="a" goto run_a
goto chk_b
:run_a
echo [%TIME%] run a: 1920x16 FRAMES=60 ADVERSARIAL
call xsim long1920x16 -R -log tb/logs_long/a_w1920_h16_f60_adversarial.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "FRAMES=60" -testplusarg ADVERSARIAL || exit /b 1
:chk_b
if "%SEL%"=="all" goto run_b
if "%SEL%"=="b" goto run_b
goto chk_e
:run_b
echo [%TIME%] run b: 160x120 FRAMES=120 ADVERSARIAL
call xsim long160 -R -log tb/logs_long/b_w160_h120_f120_adversarial.log -testplusarg "VEC=tb/vectors" -testplusarg "FRAMES=120" -testplusarg ADVERSARIAL || exit /b 1
:chk_e
if "%SEL%"=="all" goto run_e
if "%SEL%"=="e" goto run_e
goto chk_f
:run_e
echo [%TIME%] run e: 1920x1080 FRAMES=2 FULLRATE NOSWAP
call xsim long1080p -R -log tb/logs_long/e_w1920_h1080_f2_fullrate_noswap.log -testplusarg "VEC=tb/vectors_w1920_h1080" -testplusarg "FRAMES=2" -testplusarg FULLRATE -testplusarg NOSWAP || exit /b 1
:chk_f
if "%SEL%"=="all" goto run_f
if "%SEL%"=="f" goto run_f
goto chk_c
:run_f
echo [%TIME%] run f: 1920x1080 FRAMES=2 FULLRATE (mid-frame swap)
call xsim long1080p -R -log tb/logs_long/f_w1920_h1080_f2_fullrate_swap.log -testplusarg "VEC=tb/vectors_w1920_h1080" -testplusarg "FRAMES=2" -testplusarg FULLRATE || exit /b 1
:chk_c
if "%SEL%"=="all" goto run_c
if "%SEL%"=="c" goto run_c
goto chk_d
:run_c
echo [%TIME%] run c: 1920x1080 FRAMES=4 FULLRATE
call xsim long1080p -R -log tb/logs_long/c_w1920_h1080_f4_fullrate.log -testplusarg "VEC=tb/vectors_w1920_h1080" -testplusarg "FRAMES=4" -testplusarg FULLRATE || exit /b 1
:chk_d
if "%SEL%"=="all" goto run_d
if "%SEL%"=="d" goto run_d
goto done
:run_d
echo [%TIME%] run d: 1920x1080 FRAMES=3 ADVERSARIAL
call xsim long1080p -R -log tb/logs_long/d_w1920_h1080_f3_adversarial.log -testplusarg "VEC=tb/vectors_w1920_h1080" -testplusarg "FRAMES=3" -testplusarg ADVERSARIAL || exit /b 1
:done
echo [%TIME%] done
endlocal
