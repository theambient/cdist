module console;

import std.stdio;
import std.string;

enum Color
{
	NoColor,
	Bold,
	Dim,
	Red,
	Yellow,
	Green,
}

private enum string[Color] COLOR_TO_CODE =
[
	Color.Red	: "\x1b[31;01m",
	Color.Yellow: "\x1b[33m",
	Color.NoColor	: "",
	Color.Bold	: "\x1b[01m",
	Color.Dim	: "\x1b[02m",
	Color.Green	: "\x1b[32m",
];

struct Console
{
	static red(string msg){_println(Color.Red, msg);}
	static yellow(string msg){_println(Color.Yellow, msg);}
	static green(string msg){_println(Color.Green, msg);}
	static bold(string msg){_println(Color.Bold, msg);}
	static dim(string msg){_println(Color.Dim, msg);}
	static write(string msg){_println(Color.NoColor, msg);}

	private static _println(Color c, string msg)
	{
		writefln("%s%s\x1b[00m".format(
			COLOR_TO_CODE[c],
			msg,
		));
	}
}
