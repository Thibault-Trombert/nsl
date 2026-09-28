create_clock -name clk_50 -period 20 -waveform {0 10} [get_nets {clock_buf/board_clock_s}]
create_clock -name clk_96 -period 10.416667 [get_nets {ref_clock_s}]
// 122.88 MHz average, but the 6.25 VCO-cycle output divider has a
// shortest cycle of 6 / 768 MHz = 7.8125 ns. Time the fabric for it.
create_clock -name clk_audio_min -period 7.8125 [get_nets {audio_clocks_s[0]}]
