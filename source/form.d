import std.traits;
import std.base64;
import core.stdc.string : memcpy;

import vibe.d;

// Handy utility from vibe.d
private template isPublicMember(T, string M)
{
    import std.algorithm, std.typetuple : TypeTuple;

    static if (!__traits(compiles, TypeTuple!(__traits(getMember, T, M)))) enum isPublicMember = false;
    else {
        alias MEM = TypeTuple!(__traits(getMember, T, M));
        static if (__traits(compiles, __traits(getProtection, MEM)))
            enum isPublicMember = __traits(getProtection, MEM).among("public", "export");
        else
            enum isPublicMember = true;
    }
}


public void update_form_fields(T)(const(FormFields) fields, ref T form)
{
    foreach (member; __traits(allMembers, T))
    {
        static if (isPublicMember!(T, member))
        {
            mixin("alias m = form." ~ member ~ ";");

            // Imperfect test, but good enough to weed out the right properties
            // Basically we're checking for the properties generated by the bitfield mixin
            static if (isSomeFunction!m && !hasStaticMember!(T, member))
            {
                static if (!is(ReturnType!m == void))
                    alias m_type = ReturnType!m;
                else
                    alias m_type = Parameters!m[0];
                
                // Should only have uints and bools in these structures for now
                static if (is(m_type == ubyte) || is(m_type == ushort) || is(m_type == uint))
                {
                    mixin("form." ~ member ~ " = to!m_type(fields.get(\"" ~ member ~ "\", to!string(form." ~ member ~ ")));");
                }
                else static if (is(m_type == bool))
                {
                    // NOTE: Doesn't properly respect default true... need to figure out how to handle
                    // this since HTML forms don't submit anything for unchecked items
                    mixin("form." ~ member ~ " = fields.get(\"" ~ member ~ "\", \"\") == \"on\";");
                }
                else
                {
                    pragma(msg, member);
                    static assert (false);
                }
            }
        }
    }
}

public string serialize_form_to_url(T)(const(T) form)
{
    ubyte[T.sizeof] data;
    memcpy(data.ptr, &form, T.sizeof);
    return Base64URL.encode(data);
}

// NOTE: If url is empty, simply returns form defaults
public T create_form_from_url(T)(string url)
{
    T form = T.defaults();

    if (!url.empty)
    {
        // NOTE: Must handle cases where data size is less than basic form size
        // as users could be using an old link. Allow any new fields to just use defaults
        ubyte[] data = Base64URL.decode(url);    
        if (data.length > T.sizeof)
        {
            // Invalid - TODO: handle this better
            throw new HTTPStatusException(HTTPStatus.badRequest);
        }
        memcpy(&form, data.ptr, data.length);
    }

    return form;
}

public T create_form_from_fields(T)(const(FormFields) fields)
{
    T form = T.defaults();
    update_form_fields(fields, form);
    return form;
}
