
module registry;

import config;
import std.algorithm;
import std.array;
import std.process;
import std.stdio;
import std.string;
import std.exception;
import std.path;
import dyaml.all;
import exception;

struct Dependency
{
	string id;
	string vers;
}

struct Package
{
	string source;
	string vers;
	string id;
	string include_export;
	string libs_export;
	string library_export;
	string[] build_script;
	bool from_registry = true;

	Dependency[] deps;

	string fullname()
	{
		return id ~ "@" ~ vers;
	}

	string pkg_dir()
	{
		return buildPath(config.CDIST_ROOT_DIR, "cache", id.replace(" ", "_"), vers);
	}

	string dest_dir()
	{
		return buildPath(pkg_dir(), "dest");
	}

	string src_dir()
	{
		if(from_registry)
			return buildPath(pkg_dir(), "src");
		else
			return buildPath(std.file.getcwd(), source);

	}

	void dump(string filename)
	{
		Node[string] root;
		root["source"] = Node(source);
		root["version"] = Node(vers);
		root["id"] = Node(id);
		root["build"] = Node(build_script);

		Node[string] exp;
		exp["include_dir"] = Node(include_export);
		exp["library_dir"] = Node(libs_export);
		exp["library"] = Node(library_export);

		Node[] deps_nodes;
		foreach(d; deps)
		{
			auto dd = Node();
			dd["id"] = Node(d.id);
			dd["version"] = Node(d.vers);
			deps_nodes ~= dd;
		}

		root["export"] = Node(exp);
		root["deps"] = Node(deps_nodes);

		Dumper(filename).dump(Node(root));
	}
}

class Registry
{
	private immutable string registry_url = config.REGISTRY_URL;
	private immutable string registry_cache_path;

	this()
	{
		registry_cache_path = std.path.buildPath(config.CDIST_ROOT_DIR, "index");
	}

	public void update()
	{
		throw new Exception("Not Implemented");
	}

	public void init()
	{
		if(std.file.exists(registry_cache_path))
		{
			return;
		}

		writefln("initializing registry ...");

		auto r = execute(["git", "clone", registry_url, registry_cache_path]);

		if(r.status != 0)
		{
			throw new Exception("failed to init registry:\n" ~ r.output);
		}
	}

	public void add_package(Package p)
	{
		auto dir = buildPath(registry_cache_path, p.id);
		auto filepath = buildPath(dir, p.vers ~ ".yaml");

		if(!std.file.exists(dir))
		{
			std.file.mkdir(dir);
		}

		enforce!SysExitEx(!std.file.exists(filepath), "registry already contain package %s".format(p.fullname));

		p.dump(filepath);
	}

	public Package read_package(Dependency d)
	{
		auto path = buildPath(registry_cache_path, d.id, d.vers ~ ".yaml");

		return _read_package(path, true);
	}

	public Package read_package(string filename)
	{
		return _read_package(filename, false);
	}

	private Package _read_package(string filename, bool from_registry)
	{
		auto root = Loader(filename).load();

		Package p;

		p.id = root["id"].as!string;
		p.vers = root["version"].as!string;
		p.source = root["source"].as!string;

		if("deps" in root)
		{
			auto deps_list_unparsed = root["deps"];
			foreach(Node x; deps_list_unparsed)
			{
				Dependency d;

				if(x.isString)
				{
					auto s = x.as!string;
					auto toks = s.split("@");
					enforce(toks.length == 2, "invalid dependency: " ~ s);

					d.id = toks[0];
					d.vers = toks[1];
				}
				else if(x.isMapping)
				{
					d.id = x["id"].as!string;
					d.vers = x["version"].as!string;
				}
				else
				{
					throw new Exception("invalid dependency");
				}

				p.deps ~= d;
			}
		}

		foreach(Node x; root["build"])
		{
			p.build_script ~= x.as!string;
		}

		if("export" in root)
		{
			auto e = root["export"];
			p.include_export = e["include_dir"].as!string;
			p.libs_export = e["library_dir"].as!string;
			p.library_export = e["library"].as!string;
		}

		p.from_registry = from_registry;
		return p;
	}

	Package[] build_deps_list(Package p)
	{
		// TODO: make hierarchical dependency resolving
		return map!(d => read_package(d))(p.deps).array;
	}
}
