// Copyright (c) 2023-2024 Francisco Llobet-Blandino and the "Miso Project".
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the “Software”), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

const std = @import("std");
//const connection = @import("connection.zig");
pub const c = @cImport({
    @cDefine("MBEDTLS_CONFIG_FILE", "\"miso_mbedtls_config.h\"");
    @cInclude("string.h");
    @cInclude("mbedtls/ctr_drbg.h");
    @cInclude("mbedtls/timing.h");
    @cInclude("mbedtls/aes.h");
    @cInclude("mbedtls/base64.h");
    @cInclude("mbedtls/net_sockets.h");
    @cInclude("mbedtls/entropy.h");
});

pub const sha256 = @import("sha256.zig");
pub const pk = @import("pk.zig");

const MBEDTLS_TLS_PSK_WITH_AES_128_GCM_SHA256 = c.MBEDTLS_TLS_PSK_WITH_AES_128_GCM_SHA256;
const MBEDTLS_TLS_PSK_WITH_AES_128_CCM_8 = c.MBEDTLS_TLS_PSK_WITH_AES_128_CCM_8;
const MBEDTLS_TLS_PSK_WITH_AES_128_CCM = c.MBEDTLS_TLS_PSK_WITH_AES_128_CCM;

const MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8 = c.MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8;
const MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM = c.MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM;

const MBEDTLS_TLS1_3_SIG_ECDSA_SECP256R1_SHA256 = c.MBEDTLS_TLS1_3_SIG_ECDSA_SECP256R1_SHA256;
const MBEDTLS_TLS1_3_SIG_NONE = c.MBEDTLS_TLS1_3_SIG_NONE;

const MBEDTLS_SSL_IANA_TLS_GROUP_SECP256R1 = c.MBEDTLS_SSL_IANA_TLS_GROUP_SECP256R1;
const MBEDTLS_SSL_IANA_TLS_GROUP_NONE = c.MBEDTLS_SSL_IANA_TLS_GROUP_NONE;

/// PSK Ciphersuites supported by the Application
pub const ciphersuites_psk = [_]c_int{
    MBEDTLS_TLS_PSK_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_PSK_WITH_AES_128_CCM_8,
    MBEDTLS_TLS_PSK_WITH_AES_128_CCM,
    0,
};

/// EC Ciphersuites supported by the Application
pub const ciphersuites_ec = [_]c_int{
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_CCM,
    0,
};

/// Signature Algorithms supported by the Application
pub const sig_algorithms = [_]u16{
    MBEDTLS_TLS1_3_SIG_ECDSA_SECP256R1_SHA256,
    MBEDTLS_TLS1_3_SIG_NONE,
    // 0,
};

/// Groups supported by the application
pub const groups = [_]u16{
    MBEDTLS_SSL_IANA_TLS_GROUP_SECP256R1,
    MBEDTLS_SSL_IANA_TLS_GROUP_NONE,
};

pub const mbedtls_error = error{
    psk_conf_error,
    generic_error,
    init_error,
    no_sec,
};

pub const init_error = error{};

pub const mbedtls_ok: i32 = 0;
pub const mbedtls_nok: i32 = -1;
pub const ssl_context = c.mbedtls_ssl_context;
pub const ssl_config = c.mbedtls_ssl_config;

pub fn base64Decode(input: [*:0]u8, output: []u8) ![]u8 {
    var len: usize = 0;

    if (mbedtls_ok == c.mbedtls_base64_decode(output.ptr, output.len, &len, &input[0], c.strlen(input))) {
        return if (output.len >= len) output[0..len] else mbedtls_error.generic_error;
    }

    return mbedtls_error.generic_error;
}
