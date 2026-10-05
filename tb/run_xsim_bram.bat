@echo off
rem Block-RAM line-buffer variant (conv3x3_engine LB_BRAM=1): repeats every
rem engine run of run_xsim.bat, run_xsim_ext.bat and run_xsim_1080p.bat with
rem -d "TB_LB_BRAM=1". Run from the repo root with Vivado's bin on PATH, after
rem   python golden/gen_vectors.py
rem   python golden/gen_vectors_wide.py 1920 16
rem   python golden/gen_vectors_wide.py 1920 1080
rem Logs land in tb\logs_bram\. Every run must print "TB PASS".
rem (sobel_fixed has no LB_BRAM parameter and is not repeated here.)
setlocal
if not exist tb\logs_bram mkdir tb\logs_bram

rem --- run_xsim.bat: tb_engine.v, 160x120, random gaps + backpressure
call xvlog -sv -d "TB_LB_BRAM=1" rtl/conv3x3_engine.v tb/tb_engine.v || exit /b 1
call xelab -debug off tb_engine -s eng_sim_bram || exit /b 1
for %%K in (sobel scharr gaussian laplacian prewitt sharpen) do (
  call xsim eng_sim_bram -R -log tb/logs_bram/engine_%%K.log -testplusarg "CFG=tb/vectors/cfg_%%K.hex" -testplusarg "EXP2=tb/vectors/exp_%%K.hex" || exit /b 1
)

rem --- run_xsim_ext.bat: tb_engine_ext.v at 160x120 and 1920x16
call xvlog -sv -d "TB_LB_BRAM=1" rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s ext160_bram || exit /b 1
call xvlog -sv -d "TB_LB_BRAM=1" -d "TB_W=1920" -d "TB_H=16" -d "TB_CW=11" rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s ext1920_bram || exit /b 1

for %%K in (sobel scharr gaussian laplacian prewitt sharpen) do (
  call xsim ext160_bram  -R -log tb/logs_bram/w160_%%K_midframe.log  -testplusarg "VEC=tb/vectors"          -testplusarg "CASE=%%K" -testplusarg MIDFRAME || exit /b 1
  call xsim ext1920_bram -R -log tb/logs_bram/w1920_%%K_midframe.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "CASE=%%K" -testplusarg MIDFRAME || exit /b 1
)
call xsim ext160_bram  -R -log tb/logs_bram/w160_scharr_fullrate.log  -testplusarg "VEC=tb/vectors"          -testplusarg "CASE=scharr" -testplusarg FULLRATE || exit /b 1
call xsim ext1920_bram -R -log tb/logs_bram/w1920_scharr_fullrate.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "CASE=scharr" -testplusarg FULLRATE || exit /b 1
call xsim ext1920_bram -R -log tb/logs_bram/w1920_scharr_fullrate_midframe.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "CASE=scharr" -testplusarg FULLRATE -testplusarg MIDFRAME || exit /b 1
call xsim ext160_bram  -R -log tb/logs_bram/w160_sobel_enpause.log  -testplusarg "VEC=tb/vectors"          -testplusarg "CASE=sharpen" -testplusarg ENPAUSE || exit /b 1
call xsim ext1920_bram -R -log tb/logs_bram/w1920_sobel_enpause_fullrate.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "CASE=sharpen" -testplusarg ENPAUSE -testplusarg FULLRATE || exit /b 1

rem --- run_xsim_1080p.bat: one 1920x1080 frame pair, full rate + mid-frame
call xvlog -sv -d "TB_LB_BRAM=1" -d "TB_W=1920" -d "TB_H=1080" -d "TB_CW=11" rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s ext1080p_bram || exit /b 1
call xsim ext1080p_bram -R -log tb/logs_bram/w1920_h1080_scharr_fullrate_midframe.log -testplusarg "VEC=tb/vectors_w1920_h1080" -testplusarg "CASE=scharr" -testplusarg FULLRATE -testplusarg MIDFRAME || exit /b 1
endlocal
