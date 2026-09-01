library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_memory, nsl_amba, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;

entity axi4_stream_fifo_pkt_cancellable is
  generic(
    config_c : config_t;
    word_count_l2_c : integer;
    out_pkt_available_range_c: integer range 0 to integer'high := 0;
    nbr_of_region : integer
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i : in  std_ulogic;

    out_o : out master_t;
    out_i : in  slave_t;
    out_commit_i : in std_ulogic := '1';
    out_rollback_i : in std_ulogic := '0';
    out_available_o : out unsigned(word_count_l2_c downto 0);
    out_pkt_available_o : out integer range 0 to out_pkt_available_range_c;

    in_i  : in  master_t;
    in_o : out slave_t;
    in_commit_i : in std_ulogic := '1';
    in_rollback_i : in std_ulogic := '0';
    in_free_o : out unsigned(word_count_l2_c downto 0)
    );
end entity;

architecture beh of axi4_stream_fifo_pkt_cancellable is

  constant fifo_elements_c : string := "idskoul";
  constant data_fifo_width_c: positive := vector_length(config_c, fifo_elements_c);
  subtype data_fifo_word_t is std_ulogic_vector(0 to data_fifo_width_c-1);

  signal in_data_s, out_data_s : data_fifo_word_t;
  signal out_s : master_t;
  constant pkt_available_range_l2 : integer := nsl_math.arith.log2(out_pkt_available_range_c+1);
  signal pkt_counter : unsigned(pkt_available_range_l2-1 downto 0);

  -- Pointer has one extra bit to handle wraparound transparently
  subtype ptr_t is unsigned(word_count_l2_c downto 0);
  subtype mem_ptr_t is unsigned(word_count_l2_c-1 downto 0);

  constant ptr_region_incr : integer := (2**word_count_l2_c) / nbr_of_region;
  constant region_offset_bits_c : integer := nsl_math.arith.log2(ptr_region_incr);

  function to_ptr(i: integer) return ptr_t is
  begin
    return to_unsigned(i, ptr_t'length);
  end function;

  constant ptr_toggle_c : ptr_t := to_ptr(2 ** word_count_l2_c);

  type regs_t is
  record
    -- Committed space pointers
    rptr, wptr : ptr_t;
    -- Speculative space pointers
    rptr_sp, wptr_sp : ptr_t;
    -- Memory read pointer, it is in advance of one memory position to be able
    -- to ask next data word from memory
    rptr_mem: ptr_t;
    rdata_valid : std_ulogic;

    in_data_pkt_committed : std_ulogic_vector(nbr_of_region - 1 downto 0);
    out_data_pkt_to_send : std_ulogic_vector(nbr_of_region - 1 downto 0);
    windex, rindex : unsigned(nsl_math.arith.log2(nbr_of_region) - 1 downto 0);
    windex_sp, rindex_sp : unsigned(nsl_math.arith.log2(nbr_of_region) - 1 downto 0);

    reset_done: boolean;
  end record;

  signal r, rin : regs_t;

  signal s_do_write, s_do_read : std_ulogic;
  signal s_wptr_end, s_next_wregion, s_next_rregion, s_last_rregion, s_last_wregion, s_next_wregion_sp, s_next_rregion_sp : ptr_t;
  

begin

assert nbr_of_region > 1
    report "nbr_of_region must be > 1"                                                                                                                                                       
    severity failure;                                                                                                                                                                       
   
  assert (2 ** word_count_l2_c) mod nbr_of_region = 0                                                                                                                                          
      report "FIFO size must be divisible by nbr_of_region"
      severity failure;  

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.rptr <= to_ptr(0);
      r.wptr <= to_ptr(0);
      r.rptr_sp <= to_ptr(0);
      r.rptr_mem <= to_ptr(0);
      r.wptr_sp <= to_ptr(0);
      r.rdata_valid <= '0';
      r.reset_done <= false;
      r.in_data_pkt_committed <= (others => '0');
      r.out_data_pkt_to_send <= (others => '0');
      r.windex <= (others => '0');
      r.rindex <= (others => '0');
      r.windex_sp <= (others => '0');
      r.rindex_sp <= (others => '0');
    end if;
  end process;

  transition: process(r, out_i,
                      out_commit_i, out_rollback_i,
                      in_i, in_commit_i, in_rollback_i,
                      s_do_read, s_do_write, s_next_wregion, s_next_rregion,
                      s_next_wregion_sp, s_last_rregion, s_last_wregion, out_s) is
    variable in_data_to_commit, out_data_to_commit : boolean;
  begin
    rin <= r;

    rin.reset_done <= true;

    in_data_to_commit := false;
    out_data_to_commit := false;

    if is_ready(config_c, out_i) then
      rin.rdata_valid <= '0';
      rin.rptr_sp <= r.rptr_mem;
    end if;

    if s_do_read = '1' then
      rin.rdata_valid <= '1';
      rin.rptr_mem <= r.rptr_mem + 1;
      rin.rptr_sp <= r.rptr_mem;
    end if;

    if is_valid(config_c, out_s) and is_last(config_c, out_s) and is_ready(config_c, out_i) then
      out_data_to_commit := true;
      rin.rptr_mem <= s_next_rregion_sp; 
      rin.rptr_sp  <= s_next_rregion_sp;
      rin.out_data_pkt_to_send(to_integer(r.rindex_sp)) <= '1';
      rin.rindex_sp <= r.rindex_sp + 1;
    end if;

    if s_do_write = '1' then
      rin.wptr_sp <= r.wptr_sp + 1;
      if is_valid(config_c, in_i) and is_last(config_c, in_i) then 
        in_data_to_commit := true;
        rin.in_data_pkt_committed(to_integer(r.windex_sp)) <= '1';
        rin.windex_sp <= r.windex_sp + 1;
        rin.wptr_sp <= s_next_wregion_sp;
      end if;
    end if;

    if in_commit_i = '1' then
      -- avoid in_commit_i spamming issues
      if r.in_data_pkt_committed(to_integer(r.windex)) = '1' or in_data_to_commit then
        rin.in_data_pkt_committed(to_integer(r.windex)) <= '0';
        rin.windex <= r.windex + 1;
        rin.wptr <= s_next_wregion;
      end if;
    elsif in_rollback_i = '1' then
      rin.wptr            <= s_last_wregion;
      rin.wptr_sp         <= s_last_wregion;
      rin.windex_sp       <= r.windex;
      for i in 0 to nbr_of_region-1 loop
        rin.in_data_pkt_committed(i) <= '0';
      end loop;
    end if;

    if out_commit_i = '1' then
      -- avoid pointer increments when no actual data was sent (out_commit_i spamming)
      if r.out_data_pkt_to_send(to_integer(r.rindex)) = '1' or out_data_to_commit then
        rin.out_data_pkt_to_send(to_integer(r.rindex)) <= '0';
        rin.rptr   <= s_next_rregion;
        rin.rindex <= r.rindex + 1;
      end if;
    elsif out_rollback_i = '1' then                                                                                                                                                             
      rin.rptr            <= s_last_rregion;                  
      rin.rptr_mem        <= s_last_rregion;                                                                                                                                                    
      rin.rptr_sp         <= s_last_rregion;
      rin.rdata_valid     <= '0'; 
      rin.rindex_sp       <= r.rindex;  -- reset speculative index
      -- also clear stale flags between rindex and old rindex_sp                                                                                                                                
      for i in 0 to nbr_of_region-1 loop                      
        rin.out_data_pkt_to_send(i) <= '0';                                                                                                                                                     
      end loop;                                               
    end if;  
  end process;

  -- word_count_l2_c = 8, region_offset_bits_c = 6
  s_next_wregion <= (r.wptr(word_count_l2_c downto region_offset_bits_c) + 1)
                     & to_unsigned(0, region_offset_bits_c);
  s_next_wregion_sp <= (r.wptr_sp(word_count_l2_c downto region_offset_bits_c) + 1)
                        & to_unsigned(0, region_offset_bits_c);
  s_next_rregion <= (r.rptr(word_count_l2_c downto region_offset_bits_c) + 1)
                     & to_unsigned(0, region_offset_bits_c);
  s_last_rregion <= (r.rptr(word_count_l2_c downto region_offset_bits_c))
                     & to_unsigned(0, region_offset_bits_c);
  s_last_wregion <= (r.wptr(word_count_l2_c downto region_offset_bits_c))
                     & to_unsigned(0, region_offset_bits_c);
  s_next_rregion_sp <= (r.rptr_sp(word_count_l2_c downto region_offset_bits_c) + 1)
                        & to_unsigned(0, region_offset_bits_c);
  s_wptr_end <= r.rptr xor ptr_toggle_c;
  s_do_write <= to_logic(r.wptr_sp /= s_wptr_end) and to_logic(is_valid(config_c, in_i));
  s_do_read <= to_logic(r.rptr_mem /= r.wptr)
               and (to_logic(is_ready(config_c, out_i)) or not r.rdata_valid)
               and not to_logic(r.rdata_valid = '1' and is_last(config_c, out_s));
  out_available_o <= r.wptr - r.rptr;
  in_free_o <= s_wptr_end - r.wptr  when reset_n_i = '1' else (others => '-');
  in_o <= accept(config_c, r.wptr_sp /= s_wptr_end and r.reset_done);

  in_data_s <= vector_pack(config_c, fifo_elements_c, in_i);

  storage: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => mem_ptr_t'length,
      data_size_c => data_fifo_width_c,
      clock_count_c => 1,
      registered_output_c => false
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => r.wptr_sp(mem_ptr_t'range),
      write_en_i => s_do_write,
      write_data_i => in_data_s,

      read_address_i => r.rptr_mem(mem_ptr_t'range),
      read_en_i => s_do_read,
      read_data_o => out_data_s
      );

  unpack: process(out_data_s, r) is
  begin
    out_s <= vector_unpack(config_c, fifo_elements_c, out_data_s);
    out_s.valid <= r.rdata_valid;
  end process;

  out_o <= out_s;

  packet_counter_proc: process(clock_i, reset_n_i) is
    variable inc, dec: boolean;
  begin
    if reset_n_i = '0' then
      pkt_counter <= (others => '0');
    elsif rising_edge(clock_i) then
      inc := in_commit_i = '1' and
             (r.in_data_pkt_committed(to_integer(r.windex)) = '1' or
              (s_do_write = '1' and is_last(config_c, in_i)));
      dec := out_commit_i = '1' and
             (r.out_data_pkt_to_send(to_integer(r.rindex)) = '1' or
              (is_valid(config_c, out_s) and is_last(config_c, out_s) and is_ready(config_c, out_i)));
      if inc and not dec then
        pkt_counter <= pkt_counter + 1;
      elsif dec and not inc then
        pkt_counter <= pkt_counter - 1;
      end if;
    end if;
  end process;

  out_pkt_available_o <= to_integer(pkt_counter);

end architecture;
