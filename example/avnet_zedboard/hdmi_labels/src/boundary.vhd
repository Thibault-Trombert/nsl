library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_indication, nsl_data, nsl_video, nsl_color,
  nsl_bnoc, nsl_i2c, nsl_adi;
use nsl_video.terminal.all;
use nsl_video.mode.all;
use nsl_data.text.all;
use nsl_color.rgb.all;

entity boundary is
  port (
    clock_100_i : in std_ulogic;

    hd_clk_o : out std_ulogic;
    hd_de_o : out std_ulogic;
    hd_hsync_o : out std_ulogic;
    hd_vsync_o : out std_ulogic;
    hd_d_o : out std_ulogic_vector(15 downto 0);
    hd_scl_io : inout std_logic;
    hd_int_n_i : in std_ulogic;
    hd_sda_io : inout std_logic;

    ld_o : out std_ulogic_vector(0 to 7)
  );
end boundary;

architecture arch of boundary is

  constant clock_hz_c : natural := 100_000_000;
  constant mode_c : mode_t := mode_std_1280x1024p60_c;
  constant pixel_hz_c : natural := pixel_clock_hz(mode_c);

  -- Pixel clock tolerance covers modes not reachable exactly from the
  -- board crystal, sinks tolerate far more than this offset.
  constant pll_config_c : nsl_clocking.pll.pll_config_t
    := nsl_clocking.pll.pll_config(
      input_hz => clock_hz_c,
      o0 => nsl_clocking.pll.pll_output(pixel_hz_c, tolerance_ppm => 500));

  -- Palette entries
  constant color_black_c : natural := 0;
  constant color_white_c : natural := 1;
  constant color_red_c : natural := 2;
  constant color_green_c : natural := 3;
  constant color_blue_c : natural := 4;
  constant color_yellow_c : natural := 5;
  constant color_cyan_c : natural := 6;
  constant color_magenta_c : natural := 7;

  constant colors_c : rgb24_vector(0 to 7) := (
    rgb24_black, rgb24_white, rgb24_red, rgb24_lime,
    rgb24_blue, rgb24_yellow, rgb24_cyan, rgb24_magenta);

  constant index_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(components => 1, component_bits => 3);
  constant video_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(colorspace => nsl_video.pixel_stream.COLORSPACE_YCBCR422);
  constant palette_c : nsl_video.pixel_stream.pixel_vector(colors_c'range)
    := nsl_video.pixel_stream.palette(video_config_c, colors_c);

  -- 6x8 font scaled 4 times: 24x32 cells, 53 columns and 32 rows on
  -- screen.  Grid is 64x32, cropped to the screen width.
  constant labels_c : label_vector(0 to 9) := (
    text_label(1, 2, 23, color_white_c, color_black_c),
    text_label(3, 2, 24, color_cyan_c, color_black_c),
    text_label(6, 2, 7, color_red_c, color_black_c),
    text_label(7, 2, 7, color_green_c, color_black_c),
    text_label(8, 2, 7, color_blue_c, color_black_c),
    text_label(9, 2, 7, color_yellow_c, color_black_c),
    text_label(10, 2, 7, color_magenta_c, color_black_c),
    text_label(12, 2, 7, color_black_c, color_white_c),
    text_label(12, 10, 8, color_white_c, color_black_c),
    text_label(31, 47, 6, color_white_c, color_black_c)
    );

  constant text_length_c : natural := labels_text_length(labels_c);

  signal clock_s, startup_reset_n_s, reset_n_s : std_ulogic;
  signal pll_clock_s : std_ulogic_vector(0 to 0);
  signal pll_locked_s, pixel_clock_s, pixel_reset_n_s : std_ulogic;

  signal cmd_s, rsp_s : nsl_bnoc.framed.framed_bus;
  signal i2c_i_s : nsl_i2c.i2c.i2c_i;
  signal i2c_o_s : nsl_i2c.i2c.i2c_o;

  signal index_s, video_s : nsl_video.pixel_stream.bus_t;
  signal hpd_s, ready_s, synced_s, irq_n_s : std_ulogic;

  signal text_s : string(1 to text_length_c);
  signal colors_s : label_color_vector(0 to colors_c'length-1);

  signal tick_s : natural range 0 to pixel_hz_c - 1;
  signal seconds_s : unsigned(16 downto 0);

begin

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clock_100_i,
      clock_o => clock_s
      );

  roc_gen: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => startup_reset_n_s
      );

  resync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => startup_reset_n_s,
      data_o => reset_n_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => clock_s,
      clock_o => pll_clock_s,
      reset_n_i => reset_n_s,
      locked_o => pll_locked_s
      );

  pixel_clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => pll_clock_s(0),
      clock_o => pixel_clock_s
      );

  pixel_resync: nsl_clocking.async.async_edge
    port map(
      clock_i => pixel_clock_s,
      data_i => pll_locked_s,
      data_o => pixel_reset_n_s
      );

  i2c_pads: nsl_i2c.i2c.i2c_line_driver
    port map(
      bus_io.scl => hd_scl_io,
      bus_io.sda => hd_sda_io,
      bus_o => i2c_i_s,
      bus_i => i2c_o_s
      );

  i2c_master: nsl_i2c.transactor.transactor_framed_controller
    generic map(
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      i2c_o => i2c_o_s,
      i2c_i => i2c_i_s,
      cmd_i => cmd_s.req,
      cmd_o => cmd_s.ack,
      rsp_o => rsp_s.req,
      rsp_i => rsp_s.ack
      );

  irq_sync: nsl_clocking.async.async_input
    generic map(
      reset_value_c => '1'
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      data_i => hd_int_n_i,
      data_o => irq_n_s
      );

  transmitter: nsl_adi.adv7511.adv7511_driver
    generic map(
      clock_i_hz_c => clock_hz_c,
      config_c => video_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      irq_n_i => irq_n_s,

      i2c_divisor_i => nsl_i2c.transactor.scl_divisor(clock_hz_c, 400_000),
      cmd_o => cmd_s.req,
      cmd_i => cmd_s.ack,
      rsp_i => rsp_s.req,
      rsp_o => rsp_s.ack,

      -- DVI sink
      aspect_i => nsl_adi.adv7511.ASPECT_4_3,
      hdmi_i => '0',

      hpd_o => hpd_s,
      ready_o => ready_s,

      pixel_clock_i => pixel_clock_s,
      pixel_reset_n_i => pixel_reset_n_s,

      v_fp_m1_i => v_fp_m1(mode_c),
      v_sync_m1_i => v_sync_m1(mode_c),
      v_bp_m1_i => v_bp_m1(mode_c),
      v_act_m1_i => v_act_m1(mode_c),
      h_fp_m1_i => h_fp_m1(mode_c),
      h_sync_m1_i => h_sync_m1(mode_c),
      h_bp_m1_i => h_bp_m1(mode_c),
      h_act_m1_i => h_act_m1(mode_c),
      vsync_i => mode_c.v.sync,
      hsync_i => mode_c.h.sync,

      pixel_i => video_s.m,
      pixel_o => video_s.s,
      synced_o => synced_s,

      clock_o => hd_clk_o,
      de_o => hd_de_o,
      hsync_o => hd_hsync_o,
      vsync_o => hd_vsync_o,
      data_o => hd_d_o
      );

  terminal: nsl_video.terminal.terminal_labels_colormap
    generic map(
      row_count_l2_c => 5,
      column_count_l2_c => 6,
      character_count_l2_c => 8,
      color_count_l2_c => 3,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => labels_c,
      blank_color_c => color_black_c,
      font_hscale_c => 4,
      font_vscale_c => 4,
      config_c => index_config_c,
      geometry_c => geometry(mode_c)
      )
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,

      out_o => index_s.m,
      out_i => index_s.s,

      text_i => text_s,
      color_i => colors_s
      );

  expander: nsl_video.colormap.palette_expander
    generic map(
      in_config_c => index_config_c,
      out_config_c => video_config_c
      )
    port map(
      clock_i => pixel_clock_s,
      reset_n_i => pixel_reset_n_s,
      palette_i => palette_c,
      in_i => index_s.m,
      in_o => index_s.s,
      out_o => video_s.m,
      out_i => video_s.s
      );

  palette_colors: for i in colors_s'range
  generate
    colors_s(i) <= to_unsigned(i, label_color_t'length);
  end generate;

  uptime: process(pixel_clock_s, pixel_reset_n_s)
  begin
    if rising_edge(pixel_clock_s) then
      if tick_s /= pixel_hz_c - 1 then
        tick_s <= tick_s + 1;
      else
        tick_s <= 0;
        seconds_s <= seconds_s + 1;
      end if;
    end if;

    if pixel_reset_n_s = '0' then
      tick_s <= 0;
      seconds_s <= (others => '0');
    end if;
  end process;

  text_s <= "NSL ADV7511 ON ZEDBOARD"
            & "1280X1024P60 YCBCR 4:2:2"
            & "RED    "
            & "GREEN  "
            & "BLUE   "
            & "YELLOW "
            & "MAGENTA"
            & " UPTIME"
            & to_decimal_string(seconds_s, 8)
            & "CORNER";

  ld_o(0) <= hpd_s;
  ld_o(1) <= ready_s;
  ld_o(2) <= synced_s;
  ld_o(3) <= pll_locked_s;
  ld_o(4) <= seconds_s(0);
  ld_o(5 to 7) <= (others => '0');

end arch;
