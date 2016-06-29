## RESP (Redis Serialization Protocol)

Short quotes from http://redis.io/topics/protocol.  The reader is __strongly encouraged__ to read the original document.  This is a _cheat sheet_ for development reference.

Another reference that details the C language implementation of Redis Strings, entitled _Hacking Strings_ can be found at http://redis.io/topics/internals-sds

For Redis Events and their C implementation, see http://redis.io/topics/internals-rediseventlib

* Requests are sent from the client to the Redis server as arrays of strings representing the arguments of the command to execute.
* Redis replies with a command-specific data type
* binary-safe
* uses prefixed-length to transfer bulk data
* a serialization protocol that supports the following data types: __Simple Strings__, __Errors__, __Integers__, __Bulk Strings__ and __Arrays__

### RESP Response Types

* send commands to a Redis server as a RESP Array of Bulk Strings
* server replies with one of the RESP types:
    1. __Simple Strings__ the first byte of the reply is "+"
    2. __Errors__ the first byte of the reply is "-"
    3. __Integers__ the first byte of the reply is ":"
    4. __Bulk Strings__ the first byte of the reply is "$"
    5. __Arrays__ the first byte of the reply is "\*"
    6. RESP is able to represent a __Null__ value using a special variation of Bulk Strings or Array
* different parts of the protocol are always terminated with "\r\n" (CRLF)

#### Simple Strings

* `+OK\r\n`
* non binary safe strings
* for binary safe use __Bulk Strings__
* a client library should return to the caller a string composed of the first character after the '+' up to the end of the string, excluding the final CRLF bytes

#### Errors

* `-Error message\r\n`, identical to __Simple Strings__
* An exception should be raised by the library client when an Error Reply is received
* A client implementation may return different kind of exceptions for different errors, or may provide a generic way to trap errors by directly providing the error name to the caller as a string.
However, such a feature should not be considered vital as it is rarely useful, and a limited client implementation may simply return a generic error condition, such as false.

#### Integers

* `:1000\r\n`
* a CRLF terminated string representing an integer, prefixed by a ":" byte
* guaranteed to be in the range of a signed 64 bit integer
* used in order to return true or false

_Note_:  we have "OK" and 1

#### Bulk Strings

* `$6\r\nfoobar\r\n`
* single binary safe string up to 512 MB in length
* an empty string is `$0\r\n\r\n`
* a Null, or __Null Bulk String__ is `$-1\r\n`
* The client library API should not return an empty string, but a nil object, when the server replies with a Null Bulk String. For example a Ruby library should return 'nil' while a C library should return NULL (or set a special flag in the reply object), and so forth

_Note_: Julia this would be a Nullable{T}, where T is an `Integer` or `AbstractString`

#### Arrays

* `*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n` an __Array__ of 2 __Bulk Strings__
* `*0\r\n` is an empty Array
* Arrays can contain mixed types
* Single elements of an __Array__ may be __Null__: e.g., SORT command when used with the GET pattern option when the specified key is missing


__TODO__:  next section "Sending Commands to Redis"
