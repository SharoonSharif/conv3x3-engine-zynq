@echo off
rem Extended engine tests (tb/tb_engine_ext.v). Run from the repo root with
rem Vivado's bin on PATH. Regenerate the wide vectors first:
rem   python golden/gen_vectors_wide.py 1920 16
setlocal
if not exist tb\logs_ext mkdir tb\logs_ext

call xvlog -sv rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s ext160 || exit /b 1
call xvlog -sv -d "TB_W=1920" -d "TB_H=16" -d "TB_CW=11" rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s ext1920 || exit /b 1

for %%K in (sobel scharr gaussian laplacian) do (
  call xsim ext160  -R -log tb/logs_ext/w160_%%K_midframe.log  -testplusarg "VEC=tb/vectors"          -testplusarg "CASE=%%K" -testplusarg MIDFRAME || exit /b 1
  call xsim ext1920 -R -log tb/logs_ext/w1920_%%K_midframe.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "CASE=%%K" -testplusarg MIDFRAME || exit /b 1
)
call xsim ext160  -R -log tb/logs_ext/w160_scharr_fullrate.log  -testplusarg "VEC=tb/vectors"          -testplusarg "CASE=scharr" -testplusarg FULLRATE || exit /b 1
call xsim ext1920 -R -log tb/logs_ext/w1920_scharr_fullrate.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "CASE=scharr" -testplusarg FULLRATE || exit /b 1
call xsim ext1920 -R -log tb/logs_ext/w1920_scharr_fullrate_midframe.log -testplusarg "VEC=tb/vectors_w1920_h16" -testplusarg "CASE=scharr" -testplusarg FULLRATE -testplusarg MIDFRAME || exit /b 1
endlocal
