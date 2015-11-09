
module config;
import std.path;

immutable string REGISTRY_URL = "file:///Users/ruslan/Source/cdist/registry-test/";
immutable string CDIST_ROOT_DIR;

static this()
{
	CDIST_ROOT_DIR = std.path.expandTilde("~/.cdist/");
}



