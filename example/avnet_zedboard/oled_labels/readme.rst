=====================
 ZedBoard OLED labels
=====================

Displays a status screen on the ZedBoard 128x32 monochrome OLED
(UG-2832HSWEG04, SSD1306 controller), PL only.  The terminal label
generator renders a one-bit color index stream with the 6x8 font, a
palette expander turns it into a black and white gray stream for the
SSD1306 driver.  The screen shows uptime
since configuration, the count of frames sent to the panel, and a
status line that flips between normal and inverted video every two
seconds.  LD0 toggles every 32 frames as a refresh heartbeat, LD1
tells the driver is synced to the pixel stream.

Program with::

  acrobe chip -r 'hs2-/jtag/chain/0' -t Zynq --loadable config \
    program oled_labels.bit
