library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_indication, nsl_time, nsl_data, nsl_video,
  nsl_spi, nsl_solomonsystech;
use nsl_video.terminal.all;
use nsl_data.text.all;
use nsl_time.calendar.all;

entity boundary is
  port (
    clock_100_i : in std_ulogic;

    oled_dc_o : out std_ulogic;
    oled_res_n_o : out std_ulogic;
    oled_sclk_o : out std_ulogic;
    oled_sdin_o : out std_ulogic;
    oled_vbat_n_o : out std_ulogic;
    oled_vdd_n_o : out std_ulogic;

    ld_o : out std_ulogic_vector(0 to 7)
  );
end boundary;

architecture arch of boundary is

  constant clock_hz_c : natural := 100_000_000;

  constant width_c : natural := 128;
  constant height_c : natural := 32;

  -- Color port entries
  constant color_off_c : natural := 0;
  constant color_on_c : natural := 1;
  constant color_status_fg_c : natural := 2;
  constant color_status_bg_c : natural := 3;
  constant color_count_c : natural := 4;

  -- 128x32 panel with 6x8 font: 21 columns, 4 rows
  constant labels_c : label_vector(0 to 5) := (
    text_label(0, 0, 21, color_on_c, color_off_c),
    text_label(1, 0, 7, color_on_c, color_off_c, underline => true),
    text_label(1, 8, 8, color_on_c, color_off_c),
    text_label(2, 0, 7, color_on_c, color_off_c, underline => true),
    text_label(2, 8, 9, color_on_c, color_off_c),
    text_label(3, 0, 10, color_status_fg_c, color_status_bg_c)
    );

  constant text_length_c : natural := labels_text_length(labels_c);

  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1,
                                     components => 1,
                                     component_bits => 1);

  signal clock_s, internal_reset_n_s, reset_n_s : std_ulogic;

  signal pixel_s : nsl_video.pixel_stream.bus_t;
  signal synced_s, frame_end_s : std_ulogic;

  signal spi_s : nsl_spi.spi.spi_slave_i;
  signal vcc_en_s, power_en_s : std_ulogic;

  signal text_s : string(1 to text_length_c);
  signal colors_s : label_color_vector(0 to color_count_c-1);

  signal tick_counter_s : integer range 0 to clock_hz_c-1 := 0;
  signal seconds_s : unsigned(31 downto 0) := (others => '0');
  -- Frame counter kept as decimal digits, most significant first
  constant frame_digit_count_c : natural := 9;
  type digit_vector is array(0 to frame_digit_count_c-1) of unsigned(3 downto 0);
  signal frame_digits_s : digit_vector := (others => (others => '0'));
  signal frame_toggle_s : unsigned(5 downto 0) := (others => '0');

  function to_string(digits: digit_vector) return string
  is
    variable ret : string(1 to digits'length);
  begin
    for i in digits'range
    loop
      ret(i + 1) := character'val(character'pos('0') + to_integer(digits(i)));
    end loop;
    return ret;
  end function;
  signal date_time_s : date_time_t;

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clock_100_i,
      clock_o => clock_s
      );

  roc_gen: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => internal_reset_n_s
      );

  resync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => internal_reset_n_s,
      data_o => reset_n_s
      );

  display: nsl_solomonsystech.ssd1306.ssd1306_spi_driver
    generic map(
      clock_i_hz_c => clock_hz_c,
      config_c => pixel_config_c,
      width_c => width_c,
      height_c => height_c,
      com_alternative_c => false,
      charge_pump_c => true,
      -- Module is mounted upside down relative to its vendor's
      -- reference orientation
      rotate_180_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      spi_o => spi_s,
      dc_o => oled_dc_o,
      reset_n_o => oled_res_n_o,
      vcc_en_o => vcc_en_s,
      power_en_o => power_en_s,

      pixel_i => pixel_s.m,
      pixel_o => pixel_s.s,
      synced_o => synced_s
      );

  oled_sclk_o <= spi_s.sck;
  oled_sdin_o <= spi_s.mosi;
  oled_vbat_n_o <= not vcc_en_s;
  oled_vdd_n_o <= not power_en_s;

  terminal: nsl_video.terminal.terminal_labels_colormap
    generic map(
      row_count_l2_c => 2,
      column_count_l2_c => 5,
      character_count_l2_c => 8,
      color_count_l2_c => 1,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => labels_c,
      blank_color_c => color_off_c,
      underline_support_c => true,
      config_c => pixel_config_c,
      geometry_c => nsl_video.mode.geometry(width_c, height_c)
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      enable_i => '1',
      out_o => pixel_s.m,
      out_i => pixel_s.s,

      text_i => text_s,
      color_i => colors_s
      );

  frame_end_s <= '1' when nsl_video.pixel_stream.is_taken(pixel_config_c, pixel_s.m, pixel_s.s)
                 and nsl_video.pixel_stream.is_eof(pixel_config_c, pixel_s.m)
                 else '0';

  counters: process(clock_s, reset_n_s)
  begin
    if rising_edge(clock_s) then
      if tick_counter_s /= clock_hz_c - 1 then
        tick_counter_s <= tick_counter_s + 1;
      else
        tick_counter_s <= 0;
        seconds_s <= seconds_s + 1;
      end if;

      if frame_end_s = '1' then
        frame_toggle_s <= frame_toggle_s + 1;
        for i in frame_digits_s'reverse_range
        loop
          if frame_digits_s(i) /= 9 then
            frame_digits_s(i) <= frame_digits_s(i) + 1;
            exit;
          end if;
          frame_digits_s(i) <= (others => '0');
        end loop;
      end if;
    end if;

    if reset_n_s = '0' then
      tick_counter_s <= 0;
      seconds_s <= (others => '0');
      frame_toggle_s <= (others => '0');
      frame_digits_s <= (others => (others => '0'));
    end if;
  end process;

  calendar: calendar_from_seconds
    generic map(
      epoch_year_c => 1970
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      seconds_i => seconds_s,
      date_time_o => date_time_s
      );

  text_s <= "NSL SSD1306 ON ZEDBRD"
            & "UPTIME:"
            & to_decimal_string(date_time_s.hour, 2) & ":"
            & to_decimal_string(date_time_s.minute, 2) & ":"
            & to_decimal_string(date_time_s.second, 2)
            & "FRAMES:"
            & to_string(frame_digits_s)
            & if_else(seconds_s(1) = '0', "  STATUS  ", " INVERTED ");

  -- Status line flips between normal and inverted video every two
  -- seconds
  colors_s(color_off_c) <= x"00";
  colors_s(color_on_c) <= x"01";
  colors_s(color_status_fg_c) <= x"01" when seconds_s(1) = '0' else x"00";
  colors_s(color_status_bg_c) <= x"00" when seconds_s(1) = '0' else x"01";

  ld_o(0) <= frame_toggle_s(frame_toggle_s'left);
  ld_o(1) <= synced_s;
  ld_o(2 to 7) <= (others => '0');

end arch;
