"""Exercise the simulated buses from acrobe.

Run with ``acrobe run demo.py`` while the simulator is running.
"""

import argparse
import os

from acrobe.root import root


class Demo:
    AXI_PATH = "udp/{host}:4250/nsl_axi4_mm(id_width=2,max_length=16,burst=1)"
    APB_PATH = ("udp/{host}:4251/nsl_apb(address_width=16,"
                "data_bus_width=32,burst_length_l2=4)")

    def __init__(self, host):
        self.host = host

    async def axi(self):
        bus = await root(self.AXI_PATH.format(host=self.host))
        print(f"AXI: {bus.fqdn}")

        await bus.write32(0x0, 0xdeadbeef)
        print(f"  read32(0x0) = {await bus.read32(0x0):#010x}")

        pattern = os.urandom(3000)
        await bus.mem_write(0x1f03, pattern)
        back = await bus.mem_read(0x1f03, len(pattern))
        self.check("3000 bytes at 0x1f03", back == pattern)

        await bus.mem_write(0x1f05, b"\xa5")
        edges = await bus.mem_read(0x1f03, 4)
        self.check("byte write inside a word",
                   edges == pattern[:2] + b"\xa5" + pattern[3:4])

    async def apb(self):
        bus = await root(self.APB_PATH.format(host=self.host))
        print(f"APB: {bus.fqdn}")
        print(f"  identify: {await bus.identify()!r}")

        await bus.write32(0x40, 0xcafef00d)
        print(f"  read32(0x40) = {await bus.read32(0x40):#010x}")

        pattern = os.urandom(1024)
        await bus.mem_write(0x100, pattern)
        back = await bus.mem_read(0x100, len(pattern))
        self.check("1024 bytes at 0x100", back == pattern)
        self.check("unaligned read inside",
                   await bus.mem_read(0x103, 6) == pattern[3:9])

    @staticmethod
    def check(what, ok):
        print(f"  {what}: {'ok' if ok else 'MISMATCH'}")
        if not ok:
            raise SystemExit(1)


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()

    demo = Demo(args.host)
    await demo.axi()
    await demo.apb()
