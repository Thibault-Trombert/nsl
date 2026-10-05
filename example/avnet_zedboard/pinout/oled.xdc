# UG-2832HSWEG04 128x32 OLED module, SSD1306 controller.  Chip select
# is tied low on board, supply switches are active low.
set_property -dict { PACKAGE_PIN U10   IOSTANDARD LVCMOS33 } [get_ports { oled_dc_o }];
set_property -dict { PACKAGE_PIN U9    IOSTANDARD LVCMOS33 } [get_ports { oled_res_n_o }];
set_property -dict { PACKAGE_PIN AB12  IOSTANDARD LVCMOS33 } [get_ports { oled_sclk_o }];
set_property -dict { PACKAGE_PIN AA12  IOSTANDARD LVCMOS33 } [get_ports { oled_sdin_o }];
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { oled_vbat_n_o }];
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { oled_vdd_n_o }];
