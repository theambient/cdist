
module exception;

import std.exception;

class SysExitEx : Exception
{
	public const int code;

	public this(string m, string file = __FILE__, size_t line = __LINE__)
	{
		super(m, file, line);
		code = -1;
	}

	this(int code, string m = "")
	{
		super(m);
		this.code = code;
	}
}
