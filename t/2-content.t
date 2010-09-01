# vi:ft=
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(120);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 + 1);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: basic print
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua 'ngx.print("Hello, Lua!\\n")';
    }
--- request
GET /lua
--- response_body
Hello, Lua!



=== TEST 2: basic say
--- config
    location /say {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua '
            ngx.say("Hello, Lua!")
            ngx.say("Yay! ", 123)';
    }
--- request
GET /say
--- response_body
Hello, Lua!
Yay! 123



=== TEST 3: no ngx.echo
--- config
    location /lua {
        content_by_lua 'ngx.echo("Hello, Lua!\\n")';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 4: variable
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua 'v = ngx.var["request_uri"] ngx.print("request_uri: ", v, "\\n")';
    }
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 5: variable (file)
--- config
    location /lua {
        content_by_lua_file html/test.lua;
    }
--- user_files
>>> test.lua
v = ngx.var["request_uri"]
ngx.print("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 6: calc expression
--- config
    location /lua {
        content_by_lua_file html/calc.lua;
    }
--- user_files
>>> calc.lua
local function uri_unescape(uri)
    local function convert(hex)
        return string.char(tonumber("0x"..hex))
    end
    local s = string.gsub(uri, "%%([0-9a-fA-F][0-9a-fA-F])", convert)
    return s
end

local function eval_exp(str)
    return loadstring("return "..str)()
end

local exp_str = ngx.var["arg_exp"]
-- print("exp: '", exp_str, "'\n")
local status, res
status, res = pcall(uri_unescape, exp_str)
if not status then
    ngx.print("error: ", res, "\n")
    return
end
status, res = pcall(eval_exp, res)
if status then
    ngx.print("result: ", res, "\n")
else
    ngx.print("error: ", res, "\n")
end
--- request
GET /lua?exp=1%2B2*math.sin(3)%2Fmath.exp(4)-math.sqrt(2)
--- response_body
result: -0.4090441561579



=== TEST 7: read $arg_xxx
--- config
    location = /lua {
        content_by_lua 'who = ngx.var.arg_who
            ngx.print("Hello, ", who, "!")';
    }
--- request
GET /lua?who=agentzh
--- response_body chomp
Hello, agentzh!



=== TEST 8: capture location
--- config
    location /other {
        echo "hello, world";
    }

    location /lua {
        content_by_lua 'res = ngx.location.capture("/other"); ngx.print("status=", res.status, " "); ngx.print("body=", res.body)';
    }
--- request
GET /lua
--- response_body
status=200 body=hello, world



=== TEST 9: capture non-existed location
--- config
    location /lua {
        content_by_lua 'res = ngx.location.capture("/other"); ngx.print("status=", res.status)';
    }
--- request
GET /lua
--- response_body: status=404



=== TEST 10: invalid capture location (not as expected...)
--- config
    location /lua {
        content_by_lua 'res = ngx.location.capture("*(#*"); ngx.say("res=", res.status)';
    }
--- request
GET /lua
--- response_body
res=404



=== TEST 11: bad argument type to ngx.print
--- config
    location /lua {
        content_by_lua 'ngx.print(nil)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 12: bad argument type to ngx.location.capture
--- config
    location /lua {
        content_by_lua 'ngx.location.capture(nil)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 13: capture location (default 0);
--- config
 location /recur {
       content_by_lua '
           local num = tonumber(ngx.var.arg_num) or 0;
           ngx.print("num is: ", num, "\\n");

           if (num > 0) then
               res = ngx.location.capture("/recur?num="..tostring(num - 1));
               ngx.print("status=", res.status, " ");
               ngx.print("body=", res.body, "\\n");
           else
               ngx.print("end\\n");
           end
           ';
   }
--- request
GET /recur
--- response_body
num is: 0
end



=== TEST 14: capture location
--- config
 location /recur {
       content_by_lua '
           local num = tonumber(ngx.var.arg_num) or 0;
           ngx.print("num is: ", num, "\\n");

           if (num > 0) then
               res = ngx.location.capture("/recur?num="..tostring(num - 1));
               ngx.print("status=", res.status, " ");
               ngx.print("body=", res.body);
           else
               ngx.print("end\\n");
           end
           ';
   }
--- request
GET /recur?num=3
--- response_body
num is: 3
status=200 body=num is: 2
status=200 body=num is: 1
status=200 body=num is: 0
end



=== TEST 15: setting nginx variables from within Lua
--- config
 location /set {
       set $a "";
       content_by_lua 'ngx.var.a = 32; ngx.say(ngx.var.a)';
       add_header Foo $a;
   }
--- request
GET /set
--- response_headers
Foo: 32
--- response_body
32



=== TEST 16: nginx quote sql string 1
--- config
 location /set {
       set $a 'hello\n\r\'"\\';
       content_by_lua 'ngx.say(ngx.quote_sql_str(ngx.var.a))';
   }
--- request
GET /set
--- response_body
hello\n\r\'\"\\



=== TEST 17: nginx quote sql string 2
--- config
location /set {
    set $a "hello\n\r'\"\\";
    content_by_lua 'ngx.say(ngx.quote_sql_str(ngx.var.a))';
}
--- request
GET /set
--- response_body
hello\n\r\'\"\\



=== TEST 18: use dollar
--- config
location /set {
    content_by_lua '
        local s = "hello 112";
        ngx.say(string.find(s, "%d+$"))';
}
--- request
GET /set
--- response_body
79



=== TEST 19: subrequest share variables
--- config
location /sub {
    echo $a;
}
location /parent {
    set $a 12;
    content_by_lua 'res = ngx.location.capture("/sub"); ngx.print(res.body)';
}
--- request
GET /parent
--- response_body
12



=== TEST 20: set md5
--- config
    location = /md5 {
        content_by_lua 'ngx.say(ngx.md5("hello"))';
    }
--- request
GET /md5
--- response_body
5d41402abc4b2a76b9719d911017c592
