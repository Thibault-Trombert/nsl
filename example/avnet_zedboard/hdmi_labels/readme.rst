======================
 ZedBoard HDMI labels
======================

Displays a 1280x1024p60 label screen on the ZedBoard HDMI output,
through its ADV7511 transmitter, PL only.  The terminal label
generator renders color indices, a palette expander turns them into
BT.709 YCbCr 4:2:2, and the ADV7511 driver sends that on the chip
parallel bus and configures the chip over I2C, in DVI mode, whenever
a sink is plugged.  Screen shows a title, color samples and uptime.
Verified on a DVI-only 1280x1024 monitor.

LEDs: LD0 sink plugged, LD1 transmitter configured, LD2 driver synced
to the pixel stream, LD3 pixel PLL locked, LD4 toggles every second.

Program with::

  acrobe chip -r 'hs2-/jtag/chain/0' -t Zynq --loadable config \
    program hdmi_labels.bit
