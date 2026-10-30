# Compile the 8x8 matmul unit for the DE10. Takes a few minutes (much smaller than CVA6).
# Results: output_files\matmul.fit.summary (ALMs, DSP, RAM blocks) and
#          output_files\matmul.sta.rpt  (search for "Fmax Summary").
$q = "D:\Intel_Quartus_Prime\quartus\bin64"
Set-Location D:\Quartus\cva\matmul8x8
& "$q\quartus_sh.exe" --flow compile matmul -c matmul > flow_log.txt 2> flow_err.txt
Get-Content output_files\matmul.fit.summary
