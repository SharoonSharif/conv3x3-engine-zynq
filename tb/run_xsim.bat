@echo off
rem Run all self-checking testbenches with Vivado xsim.
rem Usage (from the repo root, with Vivado's bin directory on PATH):
rem   tb\run_xsim.bat
rem Logs land in tb\logs\. Every run must print "TB PASS".
setlocal
if not exist tb\logs mkdir tb\logs

call xvlog -sv rtl/conv3x3_engine.v tb/tb_engine.v || exit /b 1
call xelab -debug off tb_engine -s eng_sim || exit /b 1
for %%K in (sobel scharr gaussian laplacian) do (
  call xsim eng_sim -R -log tb/logs/engine_%%K.log -testplusarg "CFG=tb/vectors/cfg_%%K.hex" -testplusarg "EXP2=tb/vectors/exp_%%K.hex" || exit /b 1
)

call xvlog -sv rtl/sobel_fixed.v tb/tb_sobel_fixed.v || exit /b 1
call xelab -debug off tb_sobel_fixed -s sob_sim || exit /b 1
call xsim sob_sim -R -log tb/logs/sobel_fixed.log || exit /b 1
endlocal
