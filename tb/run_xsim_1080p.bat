@echo off
rem One full 1920x1080 frame pair through conv3x3_engine at full input rate,
rem kernel (Scharr) written mid-frame. Run from the repo root with Vivado's bin
rem on PATH, after:  python golden/gen_vectors_wide.py 1920 1080
if not exist tb\logs_ext mkdir tb\logs_ext
call xvlog -sv -d "TB_W=1920" -d "TB_H=1080" -d "TB_CW=11" rtl/conv3x3_engine.v tb/tb_engine_ext.v || exit /b 1
call xelab -debug off tb_engine_ext -s ext1080p || exit /b 1
call xsim ext1080p -R -log tb/logs_ext/w1920_h1080_scharr_fullrate_midframe.log -testplusarg "VEC=tb/vectors_w1920_h1080" -testplusarg "CASE=scharr" -testplusarg FULLRATE -testplusarg MIDFRAME || exit /b 1
