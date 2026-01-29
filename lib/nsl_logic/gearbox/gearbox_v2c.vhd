library ieee;
use ieee.std_logic_1164.all;

-- Variable-to-constant width gearbox (pipelined)
--
-- Pipeline stages:
--   Stage 1: Register input data and length
--   Stage 2: Shift input to correct position based on fill count
--   Stage 3: Merge shifted data into buffer, output when ready
--
-- Latency: 2 cycles from input to output
-- Buffer size: output_width_c + input_max_width_c

entity gearbox_v2c is
  generic(
    input_max_width_c : positive;
    output_width_c    : positive
    );
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    in_i       : in  std_ulogic_vector(0 to input_max_width_c - 1);
    in_len_i   : in  integer range 0 to input_max_width_c;

    out_valid_o : out std_ulogic;
    out_o       : out std_ulogic_vector(0 to output_width_c - 1)
    );
end entity;

architecture rtl of gearbox_v2c is

  constant buffer_size_c : natural := output_width_c + input_max_width_c;

  subtype fill_t is integer range 0 to buffer_size_c;

  type regs_t is record
    -- Stage 1: registered input
    s1_data : std_ulogic_vector(0 to input_max_width_c - 1);
    s1_len  : integer range 0 to input_max_width_c;

    -- Stage 2: shifted input (positioned for merge)
    s2_data : std_ulogic_vector(0 to buffer_size_c - 1);
    s2_len  : integer range 0 to input_max_width_c;

    -- Buffer state
    buffer_bits : std_ulogic_vector(0 to buffer_size_c - 1);
    fill        : fill_t;
  end record;

  signal r, rin : regs_t;
  signal merged_s : std_ulogic_vector(0 to buffer_size_c - 1);

begin

  merged_s <= r.buffer_bits or r.s2_data;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.s1_len <= 0;
      r.s2_len <= 0;
      r.fill <= 0;
    end if;
  end process;

  transition: process(r, in_i, in_len_i) is
    variable v_fill_after_merge : integer range 0 to buffer_size_c;
    variable v_will_output      : boolean;
    variable v_shift_amount     : integer range 0 to buffer_size_c;
    variable v_shifted          : std_ulogic_vector(0 to buffer_size_c - 1);
    variable v_merged           : std_ulogic_vector(0 to buffer_size_c - 1);
    variable v_new_fill         : fill_t;
  begin
    -- Compute fill after merging s2
    v_fill_after_merge := r.fill + r.s2_len;

    -- Determine if output will be produced
    v_will_output := v_fill_after_merge >= output_width_c;

    -- Compute shift amount for s1
    -- If output will happen, buffer shifts left by output_width_c
    -- So s1 data should be positioned at (fill_after_merge - output_width_c)
    if v_will_output then
      v_shift_amount := v_fill_after_merge - output_width_c;
    else
      v_shift_amount := v_fill_after_merge;
    end if;

    -- Stage 2: Shift s1 data to correct position
    v_shifted := (others => '0');
    for shift in 0 to buffer_size_c - 1 loop
      if v_shift_amount = shift then
        for len in 1 to input_max_width_c loop
          if r.s1_len = len then
            for i in 0 to len - 1 loop
              v_shifted(shift + i) := r.s1_data(i);
            end loop;
          end if;
        end loop;
      end if;
    end loop;

    -- Stage 3: Merge s2 into buffer
    v_merged := r.buffer_bits or r.s2_data;

    -- Handle output and update buffer
    if v_will_output then
      -- Shift buffer left by output_width_c
      for i in 0 to buffer_size_c - output_width_c - 1 loop
        rin.buffer_bits(i) <= v_merged(i + output_width_c);
      end loop;
      for i in buffer_size_c - output_width_c to buffer_size_c - 1 loop
        rin.buffer_bits(i) <= '0';
      end loop;
      v_new_fill := v_fill_after_merge - output_width_c;
      out_valid_o <= '1';
    else
      rin.buffer_bits <= v_merged;
      v_new_fill := v_fill_after_merge;
      out_valid_o <= '0';
    end if;

    rin.fill <= v_new_fill;

    -- Update s2 pipeline stage
    rin.s2_data <= v_shifted;
    rin.s2_len <= r.s1_len;

    -- Stage 1: Capture input (producer controls rate)
    rin.s1_data <= in_i;
    rin.s1_len <= in_len_i;
  end process;

  -- Output is the first output_width_c bits after merging
  out_o <= merged_s(0 to output_width_c - 1);

end architecture;
