const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    //const target = b.standardTargetOptions(.{});

    // Overiding the target for practice
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{
            .explicit = &std.Target.arm.cpu.cortex_m3,
        },
        .os_tag = .freestanding,
        .abi = .eabi,
    });

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mbedtls",
        .target = target,
        .optimize = optimize,
    });

    const freertos = b.dependency("freertos", .{});
    const board = b.dependency("board", .{});

    for (source_paths) |p| {
        lib.addCSourceFile(.{ .file = b.path(p), .flags = &c_flags });
    }

    for (include_path) |p| {
        lib.addIncludePath(b.path(p));
    }
    for (include_path) |p| {
        lib.installHeadersDirectory(b.path(p), "mbedtls/include", .{});
    }

    //_ = freertos;
    lib.addIncludePath(freertos.artifact("freertos").getEmittedIncludeTree().path(b, "freertos/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "board/include"));
    lib.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));

    // Process modules
    const board_module = b.addModule("mbedtls", .{
        .root_source_file = b.path("src/mbedtls.zig"),
        .target = target,
        .optimize = optimize,
    });

    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "config/include"));
    board_module.addIncludePath(freertos.artifact("freertos").getEmittedIncludeTree().path(b, "freertos/include"));
    board_module.addIncludePath(board.artifact("board").getEmittedIncludeTree().path(b, "picolib/include"));
    for (include_path) |p| {
        board_module.addIncludePath(b.path(p));
    }

    b.installArtifact(lib);
}

const c_flags = [_][]const u8{ "-DMBEDTLS_CONFIG_FILE=\"miso_mbedtls_config.h\"", "-DEFM32GG390F1024", "-Os", "-fdata-sections", "-ffunction-sections" };

const include_path = [_][]const u8{
    "mbedtls/include",
};

const base_src_path = "mbedtls/library/";

const source_paths = [_][]const u8{
    base_src_path ++ "aes.c",
    //base_src_path ++ "aesni.c",
    //base_src_path ++ "aria.c",
    base_src_path ++ "asn1parse.c",
    base_src_path ++ "asn1write.c",
    base_src_path ++ "base64.c",
    base_src_path ++ "bignum.c",
    base_src_path ++ "bignum_core.c",
    base_src_path ++ "bignum_mod.c",
    base_src_path ++ "bignum_mod_raw.c",
    //base_src_path ++ "camellia.c",
    base_src_path ++ "ccm.c",
    //base_src_path ++ "chacha20.c",
    //base_src_path ++ "chachapoly.c",
    base_src_path ++ "cipher.c",
    base_src_path ++ "cipher_wrap.c",
    base_src_path ++ "constant_time.c",
    base_src_path ++ "cmac.c",
    base_src_path ++ "ctr_drbg.c",
    base_src_path ++ "des.c",
    base_src_path ++ "dhm.c",
    base_src_path ++ "ecdh.c",
    base_src_path ++ "ecdsa.c",
    base_src_path ++ "ecjpake.c",
    base_src_path ++ "ecp.c",
    base_src_path ++ "ecp_curves.c",
    base_src_path ++ "entropy.c",
    base_src_path ++ "entropy_poll.c",
    base_src_path ++ "gcm.c",
    base_src_path ++ "hkdf.c",
    base_src_path ++ "hmac_drbg.c",
    base_src_path ++ "lmots.c",
    base_src_path ++ "lms.c",
    base_src_path ++ "md.c",
    base_src_path ++ "md5.c",
    base_src_path ++ "memory_buffer_alloc.c",
    base_src_path ++ "mps_reader.c",
    base_src_path ++ "mps_trace.c",
    base_src_path ++ "nist_kw.c",
    base_src_path ++ "oid.c",
    base_src_path ++ "padlock.c",
    base_src_path ++ "pem.c",
    base_src_path ++ "pk.c",
    base_src_path ++ "pk_wrap.c",
    base_src_path ++ "pkcs12.c",
    base_src_path ++ "pkcs5.c",
    base_src_path ++ "pkparse.c",
    base_src_path ++ "pkwrite.c",
    base_src_path ++ "platform.c",
    base_src_path ++ "platform_util.c",
    base_src_path ++ "poly1305.c",
    base_src_path ++ "psa_crypto.c",
    base_src_path ++ "psa_crypto_aead.c",
    base_src_path ++ "psa_crypto_cipher.c",
    base_src_path ++ "psa_crypto_client.c",
    base_src_path ++ "psa_crypto_ecp.c",
    base_src_path ++ "psa_crypto_hash.c",
    base_src_path ++ "psa_crypto_mac.c",
    base_src_path ++ "psa_crypto_pake.c",
    base_src_path ++ "psa_crypto_rsa.c",
    base_src_path ++ "psa_crypto_se.c",
    base_src_path ++ "psa_crypto_slot_management.c",
    base_src_path ++ "psa_crypto_storage.c",
    base_src_path ++ "psa_its_file.c",
    base_src_path ++ "rsa.c",
    base_src_path ++ "rsa_alt_helpers.c",
    base_src_path ++ "sha1.c",
    base_src_path ++ "sha256.c",
    base_src_path ++ "sha512.c",
    base_src_path ++ "threading.c",
    base_src_path ++ "timing.c",
    base_src_path ++ "version.c",
    base_src_path ++ "x509.c",
    base_src_path ++ "x509_create.c",
    base_src_path ++ "x509_crl.c",
    base_src_path ++ "x509_crt.c",
    base_src_path ++ "x509_csr.c",
    base_src_path ++ "x509write_crt.c",
    base_src_path ++ "x509write_csr.c",
    base_src_path ++ "ssl_cache.c",
    base_src_path ++ "ssl_ciphersuites.c",
    base_src_path ++ "ssl_client.c",
    base_src_path ++ "ssl_cookie.c",
    base_src_path ++ "ssl_msg.c",
    base_src_path ++ "ssl_ticket.c",
    base_src_path ++ "ssl_tls.c",
    base_src_path ++ "ssl_tls12_client.c",
    base_src_path ++ "ssl_tls12_server.c",
    base_src_path ++ "ssl_tls13_keys.c",
    base_src_path ++ "ssl_tls13_server.c",
    base_src_path ++ "ssl_tls13_client.c",
    base_src_path ++ "ssl_tls13_generic.c",
};
