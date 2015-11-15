
module url;

import std.exception;
import std.array;

struct UrlParts
{
	string scheme;
	string location;
}

UrlParts urlsplit(string s)
{
	auto parts = s.split("://");

	auto up = UrlParts();

	enforce(parts.length <= 2);

	if(parts.length > 1)
	{
		up.scheme = parts[0];
		up.location = parts[1];
	}
	else
	{
		up.location = parts[0];
	}

	return up;
}

unittest
{
	auto up = urlsplit("http://host/path/file?123");
	assert(up.scheme == "http");
	assert(up.location == "host/path/file?123");

	up = urlsplit("/host/path/file");
	assert(up.scheme == "");
	assert(up.location == "/host/path/file");

	up = urlsplit("git://host/path/file.git");
	assert(up.scheme == "git");
	assert(up.location == "host/path/file.git");
}
