S/PDIF stereo CORDIC test tone
==============================

Plug the Sipeed PMOD-Ethernet into J4 of a Tang 25K. This example sends
S/PDIF across the Ethernet magnetics on **RJ45 contacts 4 and 5** (PMOD
pins 2 and 6, J4 FPGA balls D11 and D10). A matching isolated pair at
the receiving end is needed; this is not 10BASE-T traffic. The ordinary
Ethernet TX pair (RJ45 1/2, PMOD 4/8) is idle.

Two cascaded PLLs take the board's 50 MHz oscillator to 96 MHz and then
122.88 MHz. The GW5A uses fractional output dividers inside the PLLs;
the second PLL is constrained to a 768 MHz VCO and a 6.25-cycle output
divider. Dividing its output by 20 gives the 6.144 MHz S/PDIF UI tick
for 48 kHz stereo: one UI spans 125 VCO cycles rather than alternately
eight and nine 50 MHz cycles. The fabric is timed for the shortest
PLL output cycle (7.8125 ns). The transmitter starts after both PLLs
have locked.

READY reports changes of the 96 MHz reference PLL's lock signal; DONE
reports changes of the 122.88 MHz audio PLL's lock signal. They are
monitored from the board's independent 50 MHz clock. An LED lights for
at least half a second after a lock transition, so both normally flash
once during startup and then stay off. Further flashes indicate lock
loss/reacquisition; a drop of the reference PLL can light both LEDs.

Each stereo frame contains 24-bit samples: a 1 kHz sine on the left
(channel A) and a 1 kHz cosine on the right (channel B), with amplitude
0.8 full scale. The samples come from
``nsl_signal_generator.trigonometry.rect_cordic_scaled``;
the phase advances only when the S/PDIF transmitter accepts a frame.

For checking a decoder, the U (user) block repeats the 24 ASCII bytes
``NSL SPDIF SINE COS TEST!``; the remaining 168 U bits are zero. The C
(channel status) block repeats ``00 00 00 02 0b`` followed by nineteen
zero bytes: consumer linear PCM, general category, 48 kHz, 24-bit words.
Both channels carry these same blocks. V is clear and the transmitter
generates parity and a block-start preamble every 192 frames.

Build with ``gbs -C example/sipeed_tang_25k/spdif_sine project build``.
