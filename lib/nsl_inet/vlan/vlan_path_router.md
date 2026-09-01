# vlan_path_router — design notes

One GMII port fanned out to one AXI4-Stream pipe per VLAN, and back.

Source: `lib/nsl_inet/vlan/vlan_path_router.vhd`
Drawn from: `~/Documents/System_kumi_carier_integeration/val_path_router.drawio`

---

## 1. What it does

`N = vlan_id_c'length` pipes. Pipe `i` carries VID `vlan_id_c(i)`.

```
TX  (the MAC transmits; frames leave through routed_tx_o)

  gmii_tx_i ─▶ gmii_z7_phy ─L1─▶ mac_receiver ─L2─▶ vlan_demux ─┬─▶ committed_to_axi4_stream ─▶ [fifo] ─▶ routed_tx_o(0)
                                                                ├─▶ … ─────────────────────────────────▶ routed_tx_o(1)
                                                                └─▶ … ─────────────────────────────────▶ routed_tx_o(N-1)

RX  (frames enter through routed_rx_i; the MAC receives)

  routed_rx_i(0) ─▶ [fifo] ─▶ axi4_stream_to_committed ─┐
  routed_rx_i(1) ─▶ [fifo] ─▶ axi4_stream_to_committed ─┼─▶ vlan_mux ─L2─▶ mac_transmitter ─L1─▶ gmii_z7_phy ─▶ gmii_rx_o
  routed_rx_i(N-1) ▶ [fifo] ─▶ axi4_stream_to_committed ┘
```

`[fifo]` is present only when `gen_backpressure_fifo` is true. The
`committed_to_axi4_stream` / `axi4_stream_to_committed` adapters are
present in every configuration.

`L1` = layer-1 frame format (FCS present). `L2` = `nsl_inet.mac`
boundary format (no FCS).

---

## 2. Interface

### Generics

| Generic | Type | Default | Meaning |
|---|---|---|---|
| `vlan_id_c` | `vlan_id_vector` | — | One pipe per entry, in this order. Sets `N`. |
| `native_vlan_id_c` | `vlan_id_t` | `0` | VID that untagged frames belong to. |
| `word_count_l2_c` | `integer` | `9` | Depth of **each** packet-drop fifo, log2 words (512). |
| `gen_backpressure_fifo` | `boolean` | `true` | Instantiate the per-VID fifos. |
| `gen_gmii_adpater` | `boolean` | `true` | Instantiate `gmii_z7_phy` + the mac framing. |

### Ports

| Port | Dir | Type | Active when |
|---|---|---|---|
| `reset_n_i`, `clock_i` | in | `std_ulogic` | always |
| `gmii_tx_i` | in | `gmii_io_group_t` | `gen_gmii_adpater` |
| `gmii_tx_clk_o`, `gmii_col_o`, `gmii_crs_o` | out | `std_ulogic` | `gen_gmii_adpater` |
| `gmii_rx_clk_o` | out | `std_logic` | `gen_gmii_adpater` |
| `gmii_rx_o` | out | `gmii_io_group_t` | `gen_gmii_adpater` |
| `from_mac_i` / `from_mac_o` | in / out | `committed_req` / `committed_ack` | `not gen_gmii_adpater` |
| `to_mac_o` / `to_mac_i` | out / in | `committed_req` / `committed_ack` | `not gen_gmii_adpater` |
| `routed_tx_o` / `routed_tx_i` | out / in | `master_vector` / `slave_vector` `(0 to N-1)` | always |
| `routed_rx_i` / `routed_rx_o` | in / out | `master_vector` / `slave_vector` `(0 to N-1)` | always |

All unused inputs carry defaults, so either half of the interface may be
left unconnected. Unused outputs are held idle.

The per-VID AXI4-Stream is byte wide with `tlast`
(`nsl_bnoc.axi_adapter.axi4_stream_committed_config_c`).

---

## 3. Components used

| Instance | Component | Library | Notes |
|---|---|---|---|
| `phy` | `gmii_z7_phy` | `nsl_mii.gmii` | `ipg_c` left at 96 |
| `fcs_check` | `mac_receiver` | `nsl_inet.mac` | `l1_has_fcs_c => true` |
| `fcs_append` | `mac_transmitter` | `nsl_inet.mac` | `min_frame_size_c => 64` |
| `demux` | `vlan_demux` | `nsl_inet.vlan` | `header_length_c => 0` |
| `mux` | `vlan_mux` | `nsl_inet.vlan` | `header_length_c => 0` |
| `tx_adapter` ×N | `committed_to_axi4_stream` | `nsl_bnoc.axi_adapter` | defaults: 2048 B, 16 frames |
| `rx_adapter` ×N | `axi4_stream_to_committed` | `nsl_bnoc.axi_adapter` | no generics |
| `fifo` ×2N | `axi4_stream_async_packet_drop_fifo` | `nsl_amba.stream_fifo` | `clock_count_c => 2`, both tied to `clock_i` |

---

## 4. Decisions taken (deviations from the brief)

**D1 — `routed_o` / `routed_i` split into four ports.**
The brief asked for `routed_o : out bus_vector` and
`routed_i : in out bus_vector`. `bus_t` bundles a `master_t` *and* a
`slave_t`, so a single-direction port cannot carry a working stream: the
ready signal travels the other way. `in out` is also not usable on these
unresolved record types. Every other NSL component uses the
`x_o : out master_t` / `x_i : in slave_t` pair, so this follows suit:
`routed_tx_o` + `routed_tx_i`, `routed_rx_i` + `routed_rx_o`.
*Alternative if you prefer two ports:* pack the TX master with the RX
slave into `routed_o`, and the RX master with the TX slave into
`routed_i`. Legal and complete, but the field roles become non-obvious.

**D2 — `mac_receiver` / `mac_transmitter` added.**
Not in the brief or the diagram. `gmii_z7_phy` speaks the layer-1 format
(`DA | SA | ethertype | payload | FCS | status`); `vlan_demux` and
`vlan_mux` speak the mac boundary (`… | payload | status`, no FCS).
Tag removal drops 4 bytes and tag insertion adds 4, so a frame carried
straight through would arrive with an FCS that no longer matches. The
FCS is therefore checked and stripped on the way in, recomputed on the
way out. Both stages sit **inside** the `gen_gmii_adpater` generate, so
when the adapter is bypassed the external ports are expected to already
carry mac-boundary frames.

**D3 — `from_mac_*` / `to_mac_*` directions are flipped** relative to
`gmii_z7_phy`. On the phy, `from_mac_o` is an output because the phy
*produces* what the MAC transmitted. At this entity's boundary, with the
adapter bypassed, the outside world plays the phy's role, so the same
traffic must come **in**. Hence `from_mac_i : in committed_req` /
`from_mac_o : out committed_ack`, and `to_mac_o : out committed_req` /
`to_mac_i : in committed_ack`.

**D4 — `clock_count_c => 2`, both clocks tied to `clock_i`.**
`axi4_stream_async_packet_drop_fifo` declares
`clock_count_c : natural range 1 to 2` but indexes `clock_i(1)`
unconditionally (`axi4_stream_async_packet_drop_fifo.vhd:378`), so
`clock_count_c => 1` fails elaboration. Verified. Every NSL testbench
instantiates it with 2. See **Q2**.

**D5 — syntax fixes** to the supplied port list: missing `;` after
`native_vlan_id_c`, trailing `;` before the closing paren, and `in out`
on `routed_i`.

**D6 — generic values left at defaults** where the brief was silent:
`header_length_c => 0` on demux and mux (no L1 pre-header from
`gmii_z7_phy`), `min_frame_size_c => 64`, and
`committed_to_axi4_stream` at `max_length_l2_c => 11` (2048 B frames) /
`max_packet_count_l2_c => 4` (16 frames buffered). 2048 B covers a
1500-byte MTU plus tag and FCS.

**D7 — `overrun_o` left `open`** on all 2N fifos. See **Q3**.

---

## 5. Open questions

**Q1 — `slow_tx_i` / `slow_rx_o`.** The diagram carries these two labels
near the demux and mux, but they are not in the requested port list and
nothing in the brief mentions them. They match the `slow_tx` / `slow_rx`
AXI-Stream pair on `ellisys:kumi:management_controller` in the
mercury-x2 fabric. Are they a separate management bypass pipe, or an
annotation of one of the per-VID pipes? **Not implemented.**

**Q2 — does the routed side have its own clock?**
`axi4_stream_async_packet_drop_fifo` is an *asynchronous* fifo; tying
both its domains to `clock_i` works but wastes its purpose. If the
routed pipes belong to a different domain, the entity should gain a
`routed_clock_i` port and the fifos should straddle the two. One-line
change if so.

**Q3 — should drops be observable?** Each fifo has `overrun_o`, and its
whole failure mode is silently discarding a packet. Worth surfacing as a
`std_ulogic_vector(0 to N-1)` per direction, or as a single sticky bit?

**Q4 — generic naming.** `gen_gmii_adpater` is kept exactly as supplied,
including the spelling. NSL convention would be `gen_gmii_adapter_c` and
`gen_backpressure_fifo_c` (trailing `_c` for generics). Rename?

**Q5 — where does the file belong?** It is currently in
`lib/nsl_inet/vlan/`, next to its siblings, but it pulls `nsl_mii.gmii`,
`nsl_amba.axi4_stream`, `nsl_amba.stream_fifo` and
`nsl_bnoc.axi_adapter` into what is otherwise a leaf protocol library.
`lib/nsl_inet/vlan/Makefile` has **not** been touched, so the file is not
yet part of any build. If it stays, the Makefile needs:

```make
vhdl-sources += vlan_path_router.vhd

deps += nsl_amba.axi4_stream
deps += nsl_amba.stream_fifo
deps += nsl_bnoc.axi_adapter
deps += nsl_mii.gmii
```

**Q6 — is packet-drop the intended buffering?** The generic is named
`gen_backpressure_fifo`, but this fifo explicitly generates *no*
backpressure: "if the fifo is overrun the entire pkt is dropped". If you
want the sender stalled instead, `nsl_amba.stream_fifo` has blocking
variants.

**Q7 — native VLAN.** The default `native_vlan_id_c => 0` means untagged
frames are **dropped** (VID 0 is reserved by 802.1Q and so never appears
in `vlan_id_c`). Intended, or should a real native VID be the default?

**Q8 — direction convention.** The diagram reads left to right, so "TX"
is taken as MAC → peers (out via `routed_tx_o`) and "RX" as peers → MAC.
Confirm.

**Q9 — one depth for both directions?** `word_count_l2_c` currently sizes
all 2N fifos. Split into TX and RX generics if they need different depths.

**Q10 — RX VID trust.** `vlan_mux` tags purely by pipe index, so a peer
cannot spoof a VID — but neither is anything checked. Confirm that's the
intent.

---

## 6. Verification performed

Analysed and elaborated with GHDL 4.1.0, `--std=93c -frelaxed`, against
the full NSL dependency tree (32 packages, resolved from the per-package
Makefiles with `VHDL_VERSION=1993`, `target-usage=simulation`).

- `vlan_path_router.vhd` analyses with **no errors and no warnings**
- `tests/inet/vlan_path_router/src/tb.vhd` instantiates it twice —
  `(gen_gmii_adpater, gen_backpressure_fifo) = (true, true)` and
  `(false, false)` — so every generate branch is compiled
- `ghdl -e tb` **elaborates cleanly**

No functional simulation has been run: the harness is an elaboration
check only, and there is no self-checking testbench yet.

### Pre-existing breakage in the tree (unrelated to this module)

`lib/nsl_amba/stream_fifo/axi4_stream_fifo_clean.vhd` does not analyse:

```
axi4_stream_fifo_clean.vhd:151: error: no element "do_commit" in record type "regs_t"
axi4_stream_fifo_clean.vhd:152: error: no element "do_rollback" in record type "regs_t"
```

This came out of the rebase conflict resolution in commit `5366e585`.
The file needs `do_commit_s` / `do_rollback_s` (the signals the current
base declares at line 53 and drives at 125-126), keeping the
`out_pkt_available_o => open` line that the commit was adding. It does
not affect `vlan_path_router` — nothing on its dependency path
instantiates that entity.
