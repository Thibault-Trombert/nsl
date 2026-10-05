library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_solomonsystech, nsl_video, nsl_indication, nsl_spi,
  nsl_data, nsl_simulation, nsl_color;
use nsl_solomonsystech.ssd1306.all;
use nsl_video.pixel_stream.all;
use nsl_video.terminal.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_indication.font.all;
use nsl_indication.font_6x8.all;

-- Renders a label screen as a one-bit color index stream, expands it
-- to a one-bit gray stream into the SSD1306 driver for a 128x32
-- panel, and checks every byte sent to the panel against a reference
-- image computed from the font.  Grid is wider than the panel, the
-- frame is cropped to the panel width.
entity tb is
end entity;

architecture sim of tb is

  constant clock_hz_c : natural := 1_000_000;
  constant spi_hz_c : natural := 250_000;
  constant clock_period_c : time := 1 us;

  constant width_c : natural := 128;
  constant height_c : natural := 32;
  constant column_offset_c : natural := 0;
  constant font_width_c : natural := 6;
  constant font_height_c : natural := 8;

  -- Color port entries
  constant color_off_c : natural := 0;
  constant color_on_c : natural := 1;

  constant labels_c : label_vector(0 to 3) := (
    text_label(0, 0, 16, color_on_c, color_off_c),
    text_label(1, 2, 10, color_on_c, color_off_c),
    text_label(2, 0, 7, color_off_c, color_on_c),
    text_label(3, 15, 6, color_on_c, color_off_c)
    );

  constant text_c : string := "NSL SSD1306 TEST"
                              & "0123456789"
                              & " INVERT"
                              & "CORNER";

  -- Expected screen, enough columns to cover the panel width
  constant screen_columns_c : natural := 22;
  constant screen_c : string(1 to 4 * screen_columns_c) :=
    "NSL SSD1306 TEST      "
    & "  0123456789          "
    & " INVERT               "
    & "               CORNER ";

  function cell_inverted(row, column: natural) return boolean is
  begin
    return row = 2 and column < 7;
  end function;

  function expected_pixel(x, y: natural) return std_ulogic is
    constant row : natural := y / font_height_c;
    constant column : natural := x / font_width_c;
    constant ch : natural
      := character'pos(screen_c(row * screen_columns_c + column + 1));
    constant line_c : std_ulogic_vector(0 to font_width_c - 1)
      := font_glyph_line_get(font_6x8_c, ch, y mod font_height_c);
  begin
    if cell_inverted(row, column) then
      return not line_c(x mod font_width_c);
    else
      return line_c(x mod font_width_c);
    end if;
  end function;

  function expected_byte(x, page: natural) return byte is
    variable ret: byte;
  begin
    for b in 0 to 7 loop
      ret(b) := expected_pixel(x, page * 8 + b);
    end loop;
    return ret;
  end function;

  constant init_c : byte_string(0 to init_sequence_length_c - 1)
    := init_sequence(height => height_c,
                     com_alternative => false,
                     charge_pump => true,
                     rotate_180 => false,
                     contrast => x"8f");

  constant index_config_c : config_t := config(pixels => 1,
                                               components => 1,
                                               component_bits => 1);
  constant gray_config_c : config_t := config(pixels => 1,
                                              colorspace => COLORSPACE_GRAY,
                                              component_bits => 1);
  constant palette_c : pixel_vector(0 to 1)
    := palette(gray_config_c, (color_off_c => nsl_color.rgb.rgb24_black,
                               color_on_c => nsl_color.rgb.rgb24_white));

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal spi_s : nsl_spi.spi.spi_slave_i;
  signal dc_s, panel_reset_n_s, vcc_en_s, power_en_s : std_ulogic;

  signal index_s, pixel_s : bus_t;
  signal synced_s : std_ulogic;

  signal colors_s : label_color_vector(0 to 1);

  signal done_s : boolean := false;

begin

  clock_s <= not clock_s after clock_period_c / 2 when not done_s else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 10 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  dut: nsl_solomonsystech.ssd1306.ssd1306_spi_driver
    generic map(
      clock_i_hz_c => clock_hz_c,
      config_c => gray_config_c,
      spi_hz_c => spi_hz_c,
      width_c => width_c,
      height_c => height_c,
      column_offset_c => column_offset_c,
      com_alternative_c => false
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      spi_o => spi_s,
      dc_o => dc_s,
      reset_n_o => panel_reset_n_s,
      vcc_en_o => vcc_en_s,
      power_en_o => power_en_s,

      pixel_i => pixel_s.m,
      pixel_o => pixel_s.s,
      synced_o => synced_s
      );

  colors_s(color_off_c) <= x"00";
  colors_s(color_on_c) <= x"01";

  expander: nsl_video.colormap.palette_expander
    generic map(
      in_config_c => index_config_c,
      out_config_c => gray_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      palette_i => palette_c,

      in_i => index_s.m,
      in_o => index_s.s,

      out_o => pixel_s.m,
      out_i => pixel_s.s
      );

  terminal: nsl_video.terminal.terminal_labels_colormap
    generic map(
      row_count_l2_c => 2,
      column_count_l2_c => 5,
      character_count_l2_c => 8,
      color_count_l2_c => 1,
      font_c => font_6x8_c,
      labels_c => labels_c,
      blank_color_c => color_off_c,
      config_c => index_config_c,
      geometry_c => nsl_video.mode.geometry(width_c, height_c)
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      out_o => index_s.m,
      out_i => index_s.s,

      text_i => text_c,
      color_i => colors_s
      );

  monitor: process is
    procedure expect(constant v: byte;
                     constant dc: std_ulogic;
                     constant msg: string) is
      variable sh: byte;
    begin
      for i in 0 to 7 loop
        wait until rising_edge(spi_s.sck);
        assert spi_s.cs_n = '0'
          report msg & ": CS released mid-byte"
          severity failure;
        assert power_en_s = '1' and panel_reset_n_s = '1'
          report msg & ": panel not powered or held in reset"
          severity failure;
        sh := sh(6 downto 0) & spi_s.mosi;
      end loop;
      assert dc_s = dc
        report msg & ": bad D/C"
        severity failure;
      assert sh = v
        report msg & ": expected " & to_hex_string(v)
        & ", got " & to_hex_string(sh)
        severity failure;
    end procedure;

    procedure expect_setup(constant msg: string) is
    begin
      expect(cmd_column_address, '0', msg & " column address");
      expect(to_byte(column_offset_c), '0', msg & " column start");
      expect(to_byte(column_offset_c + width_c - 1), '0', msg & " column end");
      expect(cmd_page_address, '0', msg & " page address");
      expect(x"00", '0', msg & " page start");
      expect(to_byte(height_c / 8 - 1), '0', msg & " page end");
    end procedure;

    procedure expect_page(constant page: natural; constant msg: string) is
    begin
      for x in 0 to width_c - 1 loop
        expect(expected_byte(x, page), '1', msg & " page "
               & integer'image(page) & " column " & integer'image(x));
      end loop;
    end procedure;
  begin
    for i in init_c'range loop
      expect(init_c(i), '0', "init byte " & integer'image(i));
    end loop;

    expect_setup("frame 1");
    for page in 0 to height_c / 8 - 1 loop
      assert vcc_en_s = '0'
        report "Panel supply up before first frame is sent"
        severity failure;
      expect_page(page, "frame 1");
    end loop;

    -- Display-on proves the whole first frame was streamed
    expect(cmd_display_on, '0', "display on");
    assert vcc_en_s = '1'
      report "Display on without panel supply"
      severity failure;
    assert synced_s = '1'
      report "Driver not synced to stream"
      severity failure;

    expect_setup("frame 2");
    for page in 0 to height_c / 8 - 1 loop
      expect_page(page, "frame 2");
    end loop;

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  watchdog: process is
  begin
    wait for 10 sec;
    assert false
      report "Timeout"
      severity failure;
  end process;

end architecture;
