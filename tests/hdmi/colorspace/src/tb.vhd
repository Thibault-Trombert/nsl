library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hdmi, nsl_dvi, nsl_video, nsl_data, nsl_simulation;
use nsl_video.pixel_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_dvi.encoder.all;

-- Checks what an HDMI source derives from a pixel stream
-- configuration: the AVI infoframe bytes and the TMDS channel map.
entity tb is
end entity;

architecture sim of tb is

  procedure check_avi(constant name: string;
                      constant cfg: config_t;
                      constant pb1_5: byte_string)
  is
    constant di: nsl_hdmi.hdmi.data_island_t := nsl_hdmi.hdmi.di_avi(cfg);
    variable sum: natural;
  begin
    assert di.packet_type = x"82"
      report name & ": bad packet type " & to_hex_string(di.packet_type)
      severity failure;
    assert di.hb(1) = x"02"
      report name & ": bad version " & to_hex_string(di.hb(1))
      severity failure;
    assert di.hb(2) = x"0d"
      report name & ": bad length " & to_hex_string(di.hb(2))
      severity failure;
    assert di.pb(1 to 5) = pb1_5
      report name & ": bad data bytes 1-5, expected " & to_hex_string(pb1_5)
      & ", got " & to_hex_string(di.pb(1 to 5))
      severity failure;
    assert di.pb(6 to 27) = byte_string'(6 to 27 => x"00")
      report name & ": bad data bytes 6-27 " & to_hex_string(di.pb(6 to 27))
      severity failure;

    sum := to_integer(unsigned(di.packet_type))
           + to_integer(unsigned(di.hb(1)))
           + to_integer(unsigned(di.hb(2)));
    for i in di.pb'range
    loop
      sum := sum + to_integer(unsigned(di.pb(i)));
    end loop;
    assert sum mod 256 = 0
      report name & ": bad checksum " & to_hex_string(di.pb(0))
      severity failure;
  end procedure;

  procedure check_map(constant name: string;
                      constant cfg: config_t;
                      constant map_in, expected: channel_map_t)
  is
    constant got: channel_map_t := channel_map_resolve(cfg, map_in);
  begin
    for i in got'range
    loop
      assert got(i) = expected(i)
        report name & ": channel " & integer'image(i)
        & " takes component " & integer'image(got(i))
        & ", expected " & integer'image(expected(i))
        severity failure;
    end loop;
  end procedure;

begin

  checker: process is
  begin
    -- Data bytes 1 to 5:
    -- 0 Y1 Y0 A0 B1 B0 S1 S0 / C1 C0 M1 M0 R3-R0
    -- ITC EC2-EC0 Q1 Q0 SC1 SC0 / VIC / YQ1 YQ0 CN1 CN0 PR3-PR0
    check_avi("RGB full",
              config(pixels => 1),
              from_hex("0200080040"));
    check_avi("RGB limited",
              config(pixels => 1, quantization => QUANTIZATION_LIMITED),
              from_hex("0200040000"));
    check_avi("YCbCr 4:4:4 BT.709 limited",
              config(pixels => 1, colorspace => COLORSPACE_YCBCR444),
              from_hex("4280000000"));
    check_avi("YCbCr 4:4:4 BT.601 full",
              config(pixels => 1, colorspace => COLORSPACE_YCBCR444,
                     colorimetry => COLORIMETRY_BT601,
                     quantization => QUANTIZATION_FULL),
              from_hex("4240000040"));
    check_avi("YCbCr 4:2:2 BT.601 limited",
              config(pixels => 1, colorspace => COLORSPACE_YCBCR422,
                     colorimetry => COLORIMETRY_BT601),
              from_hex("2240000000"));

    check_map("RGB auto",
              config(pixels => 1),
              channel_map_auto_c, (2, 1, 0));
    check_map("YCbCr 4:4:4 auto",
              config(pixels => 1, colorspace => COLORSPACE_YCBCR444),
              channel_map_auto_c, (1, 0, 2));
    check_map("YCbCr 4:2:2 auto",
              config(pixels => 1, colorspace => COLORSPACE_YCBCR422),
              channel_map_auto_c, channel_map_auto_c);
    check_map("Gray auto",
              config(pixels => 1, colorspace => COLORSPACE_GRAY),
              channel_map_auto_c, channel_map_auto_c);
    check_map("Indexed auto",
              config(pixels => 1, components => 1),
              channel_map_auto_c, channel_map_auto_c);
    check_map("RGB explicit",
              config(pixels => 1),
              (0, 1, 2), (0, 1, 2));
    check_map("YCbCr 4:4:4 explicit RGB",
              config(pixels => 1, colorspace => COLORSPACE_YCBCR444),
              channel_map_rgb_c, (2, 1, 0));

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
