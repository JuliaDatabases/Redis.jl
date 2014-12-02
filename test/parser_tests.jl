using Base.Test

function parse_simple_string_reply_test()
    reply = "+simple test case\r\n"
    response = parse_reply(reply)
    @test response.response == "simple test case"

    reply = "+\r\n"
    response = parse_reply(reply)
    @test response.response == ""
end

function parse_integer_reply_test()
    reply = ":123\r\n"
    response = parse_reply(reply)
    @test response.response == 123

    reply = ":9\r\n"
    response = parse_reply(reply)
    @test response.response == 9

    reply = ":-7\r\n"
    response = parse_reply(reply)
    @test response.response == -7
end

function parse_bulk_reply_test()
    reply = "\$5\r\nhello\r\n"
    response = parse_reply(reply)
    @test response.response == "hello"

    reply = "\$11\r\nhello there\r\n"
    response = parse_reply(reply)
    @test response.response == "hello there"

    reply = "\$12\r\nhello\r\nworld\r\n"
    response = parse_reply(reply)
    @test response.response == "hello\r\nworld"

    reply = "\$0\r\n\r\n"
    response = parse_reply(reply)
    @test response.response == ""

    reply = "\$-1\r\n"
    response = parse_reply(reply)
    @test response.response == nothing
end

function parse_array_reply_test()
    reply = "*3\r\n:12\r\n+hello\r\n\$5\r\nworld\r\n"
    response = parse_reply(reply)
    @test response.response == [12, "hello", "world"]

    reply = "*-1\r\n"
    response = parse_reply(reply)
    @test response.response == nothing

    reply = "*4\r\n:12\r\n+hello\r\n\$5\r\nworld\r\n*2\r\n:3\r\n:4\r\n"
    response = parse_reply(reply)
    @test response.response[1:3] == [12, "hello", "world"]
    @test response.response[4] == [3, 4]
end

function parse_error_reply_test()
    reply = "-ERROR testing this\r\n"
    @test_throws ServerException parse_reply(reply)
end

function parse_reply_malformed_test()
    reply = "badreply"
    @test_throws ProtocolException parse_reply(reply)

    reply = ""
    @test_throws ProtocolException parse_reply(reply)
end

function pack_command_test()
    command = ["get", "mything"]
    packed = pack_command(command)
    @test packed == "*2\r\n\$3\r\nget\r\n\$7\r\nmything\r\n"

    command = ["ping"]
    packed = pack_command(command)
    @test packed == "*1\r\n\$4\r\nping\r\n"
end

parse_simple_string_reply_test()
parse_integer_reply_test()
parse_bulk_reply_test()
parse_array_reply_test()
parse_error_reply_test()
parse_reply_malformed_test()
pack_command_test()
