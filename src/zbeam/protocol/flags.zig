// Distribution capabilities are bit positions in one 64-bit `N` handshake
// field. A bit is advertised only when the corresponding wire behavior is
// implemented; setting an aspirational bit would make OTP send unsupported
// terms or framing. Hex keeps protocol bit positions auditable.
pub const published: u64 = 0x0000_0001;
pub const extended_references: u64 = 0x0000_0004;
pub const dist_monitor: u64 = 0x0000_0008;
pub const fun_tags: u64 = 0x0000_0010;
pub const new_fun_tags: u64 = 0x0000_0080;
pub const extended_pids_ports: u64 = 0x0000_0100;
pub const export_ptr_tag: u64 = 0x0000_0200;
pub const bit_binaries: u64 = 0x0000_0400;
pub const new_floats: u64 = 0x0000_0800;
pub const utf8_atoms: u64 = 0x0001_0000;
pub const map_tag: u64 = 0x0002_0000;
pub const big_creation: u64 = 0x0004_0000;
pub const handshake_23: u64 = 0x0100_0000;
pub const unlink_id: u64 = 0x0200_0000;
pub const mandatory_25_digest: u64 = 0x0000_0010_0000_0000;
pub const v4_nc: u64 = 0x0000_0004_0000_0000;

/// Conservative capabilities for the no-atom-cache M1 path.
///
/// `mandatory_25_digest` is bit 36 (`1 << 36`), which explains why it crosses
/// the low 32-bit word. `v4_nc` is bit 34. Both still fit the eight-octet `u64`
/// flag field sent by the OTP 23+ handshake.
pub const m1 = published |
    extended_references |
    dist_monitor |
    fun_tags |
    new_fun_tags |
    extended_pids_ports |
    export_ptr_tag |
    bit_binaries |
    new_floats |
    utf8_atoms |
    map_tag |
    big_creation |
    handshake_23 |
    unlink_id |
    mandatory_25_digest |
    v4_nc;
