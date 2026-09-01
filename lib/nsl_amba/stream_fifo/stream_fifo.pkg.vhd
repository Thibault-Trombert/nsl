library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package stream_fifo is

  -- Single or dual-clock stream fifo
  component axi4_stream_fifo is
    generic(
      config_c : nsl_amba.axi4_stream.config_t;
      depth_c : positive range 4 to positive'high;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;
      in_free_o : out integer range 0 to depth_c;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;
      out_available_o : out integer range 0 to depth_c + 1
      );
  end component;

  -- Single-clock register slice (i.e. a 3-depth fifo).
  -- Totally decouples input clocking constraints from output ones.
  -- Has at least one cycle latency.
  component axi4_stream_slice is
    generic(
      config_c : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

  -- Stream CDC. Does it by resynchronizing handshake both ways. Takes
  -- at most 2 slow + 2 fast clock cycles for one beat crossing.
  component axi4_stream_cdc is
    generic(
      config_c : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i : in std_ulogic_vector(0 to 1);
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

  -- Cancellable fifo handling AXI4 stream, do not support
  -- 2 differents clock
  component axi4_stream_fifo_cancellable is
    generic(
      config_c : nsl_amba.axi4_stream.config_t;
      word_count_l2_c : integer;
      out_pkt_available_range_c: integer range 0 to integer'high := 0
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i : in  std_ulogic;
  
      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in  nsl_amba.axi4_stream.slave_t;
      out_commit_i : in std_ulogic := '1';
      out_rollback_i : in std_ulogic := '0';
      out_available_o : out unsigned(word_count_l2_c downto 0);
      out_pkt_available_o : out integer range 0 to out_pkt_available_range_c;
  
      in_i  : in  nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;
      in_commit_i : in std_ulogic := '1';
      in_rollback_i : in std_ulogic := '0';
      in_free_o : out unsigned(word_count_l2_c downto 0)
      );
  end component;

  -- AXI4-Stream FIFO with packet-level commit/rollback on both input and output sides.
  --
  -- The internal memory is divided into nbr_of_region equal-sized slots, each holding
  -- at most one packet. Total memory is 2^word_count_l2_c words, so each slot is
  -- 2^word_count_l2_c / nbr_of_region words. The FIFO size must be divisible by
  -- nbr_of_region, and nbr_of_region must be > 1.
  --
  -- Input side:
  --   Data is written speculatively word by word. On the last beat, the write pointer
  --   snaps to the next slot boundary, skipping any unused words in the current slot.
  --   The packet becomes visible to the output only after in_commit_i is asserted,
  --   which advances the committed write pointer by one slot. in_rollback_i discards
  --   all speculatively written data since the last commit.
  --
  -- Output side:
  --   The output pre-fetches data up to the committed write boundary — speculatively
  --   written but not yet committed input data is never visible. On the last beat,
  --   the read pointer snaps to the next slot boundary. out_commit_i advances the
  --   committed read pointer by one slot, permanently consuming the packet.
  --   out_rollback_i rewinds all read pointers to the last committed read position:
  --   the same packet(s) will be re-presented from the start of that slot.
  --
  -- out_pkt_available_o counts packets committed on the input side but not yet
  -- committed on the output side. Only meaningful when out_pkt_available_range_c > 0.
  --
  -- Commit and rollback must not be asserted simultaneously on the same port.
  -- After rollback, the port may not be ready on the next cycle; handshaking is
  -- always correct.
  component axi4_stream_fifo_pkt_cancellable is
    generic(
      config_c                   : nsl_amba.axi4_stream.config_t;
      word_count_l2_c            : integer;
      out_pkt_available_range_c  : integer range 0 to integer'high := 0;
      nbr_of_region              : integer
      );
    port(
      reset_n_i : in  std_ulogic;
      clock_i   : in  std_ulogic;

      out_o             : out nsl_amba.axi4_stream.master_t;
      out_i             : in  nsl_amba.axi4_stream.slave_t;
      out_commit_i      : in  std_ulogic := '1';
      out_rollback_i    : in  std_ulogic := '0';
      out_available_o   : out unsigned(word_count_l2_c downto 0);
      out_pkt_available_o : out integer range 0 to out_pkt_available_range_c;

      in_i          : in  nsl_amba.axi4_stream.master_t;
      in_o          : out nsl_amba.axi4_stream.slave_t;
      in_commit_i   : in  std_ulogic := '1';
      in_rollback_i : in  std_ulogic := '0';
      in_free_o     : out unsigned(word_count_l2_c downto 0)
      );
  end component;

  -- Output only full AXI4-Stream packets.
  component axi4_stream_fifo_atomic is
    generic (
      config_c  : nsl_amba.axi4_stream.config_t;
      depth_c     : natural;
      txn_depth_c : natural := 4;
      clk_count_c : natural range 1 to 2
    );
    port (
        reset_n_i : in std_ulogic;
        clock_i   : in std_ulogic_vector(0 to clk_count_c - 1);

        in_i : in  nsl_amba.axi4_stream.master_t;
        in_o : out nsl_amba.axi4_stream.slave_t;

        out_o : out nsl_amba.axi4_stream.master_t;
        out_i : in  nsl_amba.axi4_stream.slave_t
    );
  end component;

  -- If in_error_i is asserted during an AXI4-Stream packet transmission,
  -- The packet is dropped.
  component axi4_stream_fifo_clean is
    generic (
        fifo_word_count_l2 : natural  := 11;
        config_c : nsl_amba.axi4_stream.config_t
    );
    port (
        clock_i   : in std_ulogic;
        reset_n_i : in std_ulogic;

        in_i : in  nsl_amba.axi4_stream.master_t;
        in_error_i : in std_ulogic;
        in_o : out nsl_amba.axi4_stream.slave_t;
        in_free_o : out unsigned(fifo_word_count_l2 downto 0);

        out_o : out nsl_amba.axi4_stream.master_t;
        out_i : in  nsl_amba.axi4_stream.slave_t;
        out_available_o : out unsigned(fifo_word_count_l2 downto 0)
    );
  end component;
  -- Asynchronous AXI4-Stream FIFO designed to transfer full packets between two independent clock domains.
  -- No back-pressure on the input interface is generated, if the fifo is overrun the entire pkt is dropped.
  component axi4_stream_async_packet_drop_fifo is
    generic (
        config_c        : nsl_amba.axi4_stream.config_t;
        word_count_l2_c : integer;
        clock_count_c   : natural range 1 to 2
    );
    port (
        reset_n_i : in std_ulogic;
        clock_i   : in std_ulogic_vector(0 to clock_count_c - 1);

        error_i : in std_ulogic := '0';

        in_i : in  nsl_amba.axi4_stream.master_t;
        in_o : out nsl_amba.axi4_stream.slave_t;

        out_i : in  nsl_amba.axi4_stream.slave_t;
        out_o : out nsl_amba.axi4_stream.master_t;
        
        -- Validation port
        overrun_o : out std_ulogic

    );
  end component;

end package stream_fifo;
