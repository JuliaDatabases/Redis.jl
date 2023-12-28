function client_tls_config(cacrtfile::AbstractString,
    clientcrtfile::Union{Nothing,AbstractString}=nothing,
    clientkeyfile::Union{Nothing,AbstractString}=nothing,
    verify::Bool=true
)
    cacrt = MbedTLS.crt_parse_file(cacrtfile)
    clientcrt = (clientcrtfile === nothing) ? nothing : MbedTLS.crt_parse_file(clientcrtfile)
    clientkey = (clientkeyfile === nothing) ? nothing : MbedTLS.parse_keyfile(clientkeyfile)
    client_tls_config(cacrt, clientcrt, clientkey, verify)
end

function client_tls_config(cacrt::Union{Nothing,MbedTLS.CRT}=nothing,
    clientcrt::Union{Nothing,MbedTLS.CRT}=nothing,
    clientkey::Union{Nothing,MbedTLS.PKContext}=nothing,
    verify::Bool=true
)

    conf = MbedTLS.SSLConfig()
    MbedTLS.config_defaults!(conf)

    entropy = MbedTLS.Entropy()
    rng = MbedTLS.CtrDrbg()
    MbedTLS.seed!(rng, entropy)
    MbedTLS.rng!(conf, rng)

    MbedTLS.authmode!(conf, verify ? MbedTLS.MBEDTLS_SSL_VERIFY_REQUIRED : MbedTLS.MBEDTLS_SSL_VERIFY_NONE)

    (cacrt === nothing) || MbedTLS.ca_chain!(conf, cacrt)
    (clientcrt === nothing) || (clientkey === nothing) || MbedTLS.own_cert!(conf, clientcrt, clientkey)

    return conf
end
