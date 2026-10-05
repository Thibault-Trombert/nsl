library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity palette_expander is
  generic(
    in_config_c : nsl_video.pixel_stream.config_t;
    out_config_c : nsl_video.pixel_stream.config_t
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    palette_i : in nsl_video.pixel_stream.pixel_vector(0 to 2**in_config_c.component_bits-1);

    in_i : in nsl_video.pixel_stream.master_t;
    in_o : out nsl_video.pixel_stream.slave_t;

    out_o : out nsl_video.pixel_stream.master_t;
    out_i : in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of palette_expander is

  subtype index_t is unsigned(in_config_c.component_bits-1 downto 0);

  constant chroma_subsampled_c : boolean
    := out_config_c.colorspace = COLORSPACE_YCBCR422;

  -- What a beat carries besides its colour, and which travels with
  -- it through the lookup.  Odd tells which chroma a 4:2:2 pixel
  -- takes.
  type framing_t is
  record
    sof, last, eof, error, odd: boolean;
  end record;

  type state_t is (
    ST_RESET,
    -- Nothing to hand out.
    ST_EMPTY,
    -- A pixel is on offer, and the input may be taken into it.
    ST_PIPE,
    -- A pixel is on offer and another index waits behind it.
    ST_FULL
    );

  type regs_t is
  record
    state: state_t;
    -- Next pixel taken from the input is an odd one in its line.
    odd: boolean;
    index: index_t;
    index_framing: framing_t;
    pixel: pixel_t;
    pixel_framing: framing_t;
  end record;

  signal r, rin: regs_t;

begin

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A palette is looked up one pixel at a time",
      condition_c => in_config_c.pixel_count = 1 and out_config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  index_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Palette expander takes an indexed stream",
      condition_c => in_config_c.colorspace = COLORSPACE_INDEXED
      )
    port map(
      unused_i => '0'
      );

  color_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Palette expander produces colors, not indices",
      condition_c => out_config_c.colorspace /= COLORSPACE_INDEXED
      )
    port map(
      unused_i => '0'
      );

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.odd <= false;
    end if;
  end process;

  transition: process(r, palette_i, in_i, out_i) is
    variable index: index_t;
    variable framing: framing_t;
    variable valid, ready, taken: boolean;

    -- A 4:2:2 pixel keeps the chroma its position takes
    function subsampled(entry: pixel_t; framing: framing_t) return pixel_t
    is
      variable ret: pixel_t;
    begin
      ret := entry;
      if chroma_subsampled_c then
        if framing.odd then
          ret(1) := ret(2);
        end if;
        ret(2) := (others => '0');
      end if;
      return ret;
    end function;
  begin
    rin <= r;

    index := resize(pixel(in_config_c, in_i)(0), index_t'length);
    framing := framing_t'(sof => is_sof(in_config_c, in_i),
                          last => is_last(in_config_c, in_i),
                          eof => is_eof(in_config_c, in_i),
                          error => is_error(in_config_c, in_i),
                          odd => r.odd);
    valid := is_valid(in_config_c, in_i);
    ready := is_ready(out_config_c, out_i);
    taken := false;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_EMPTY;

      when ST_EMPTY =>
        if valid then
          taken := true;
          rin.pixel <= subsampled(palette_i(to_integer(index)), framing);
          rin.pixel_framing <= framing;
          rin.state <= ST_PIPE;
        end if;

      when ST_PIPE =>
        if ready then
          if valid then
            taken := true;
            rin.pixel <= subsampled(palette_i(to_integer(index)), framing);
            rin.pixel_framing <= framing;
          else
            rin.state <= ST_EMPTY;
          end if;
        elsif valid then
          taken := true;
          rin.index <= index;
          rin.index_framing <= framing;
          rin.state <= ST_FULL;
        end if;

      when ST_FULL =>
        if ready then
          rin.pixel <= subsampled(palette_i(to_integer(r.index)), r.index_framing);
          rin.pixel_framing <= r.index_framing;
          rin.state <= ST_PIPE;
        end if;
    end case;

    if taken then
      rin.odd <= not r.odd and not framing.last;
    end if;
  end process;

  moore: process(r) is
  begin
    in_o <= accept(in_config_c, ready => false);
    out_o <= transfer(cfg => out_config_c,
                      pixel => pixel_dontcare_c,
                      valid => false);

    case r.state is
      when ST_RESET =>
        null;

      when ST_EMPTY =>
        in_o <= accept(in_config_c, ready => true);

      when ST_PIPE | ST_FULL =>
        if r.state = ST_PIPE then
          in_o <= accept(in_config_c, ready => true);
        end if;

        out_o <= transfer(cfg => out_config_c,
                          pixel => r.pixel,
                          valid => true,
                          sof => r.pixel_framing.sof,
                          last => r.pixel_framing.last,
                          eof => r.pixel_framing.eof,
                          error => r.pixel_framing.error);
    end case;
  end process;

end architecture;
