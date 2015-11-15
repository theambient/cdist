
module registry;

import config;
import std.algorithm;
import std.array;
import std.process;
import std.stdio;
import std.string;
import std.exception;
import std.path;
import yaml = dyaml.all;
import exception;
import console;

struct Dependency
{
	string id;
	string vers_min;
	string vers_max;

	this(string id, string vers)
	{
		this.id = id;
		this.vers_min = vers;
		this.vers_max = vers;
	}
}

struct PackageDesc
{
	string id;
	string vers;

	string fullname()
	{
		return id ~ "@" ~ vers;
	}
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
		yaml.Node[string] root;
		root["source"] = yaml.Node(source);
		root["version"] = yaml.Node(vers);
		root["id"] = yaml.Node(id);
		root["build"] = yaml.Node(build_script);

		yaml.Node[string] exp;
		exp["include_dir"] = yaml.Node(include_export);
		exp["library_dir"] = yaml.Node(libs_export);
		exp["library"] = yaml.Node(library_export);

		yaml.Node[] deps_nodes;
		foreach(d; deps)
		{
			auto dd = yaml.Node();
			dd["id"] = yaml.Node(d.id);
			dd["vers_min"] = yaml.Node(d.vers_min);
			dd["vers_max"] = yaml.Node(d.vers_max);
			deps_nodes ~= dd;
		}

		root["export"] = yaml.Node(exp);
		root["deps"] = yaml.Node(deps_nodes);

		yaml.Dumper(filename).dump(yaml.Node(root));
	}
}

interface IRegistry
{
	void update();
	void init();
	void add_package(Package p);
	Package read_package(PackageDesc d);
	Package read_package(string filename);
	Package[] build_deps_list(Package p);
}

class Registry : IRegistry
{
	private immutable string registry_url = config.REGISTRY_URL;
	private immutable string registry_cache_path;

	this()
	{
		registry_cache_path = std.path.buildPath(config.CDIST_ROOT_DIR, "index");
	}

	public override void update()
	{
		Console.bold("updating registry %s".format(registry_url));

		auto r = execute(["git", "push"], null, Config.none, size_t.max, registry_cache_path);

		if(r.status != 0)
		{
			throw new Exception("failed to update registry:\n" ~ r.output);
		}
	}

	public override void init()
	{
		if(std.file.exists(registry_cache_path))
		{
			return;
		}

		Console.bold("initializing registry %s".format(registry_url));

		auto r = execute(["git", "clone", registry_url, registry_cache_path]);

		if(r.status != 0)
		{
			throw new Exception("failed to init registry:\n" ~ r.output);
		}
	}

	public override void add_package(Package p)
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

	public override Package read_package(PackageDesc d)
	{
		auto path = buildPath(registry_cache_path, d.id, d.vers ~ ".yaml");

		return _read_package(path, true);
	}

	public override Package read_package(string filename)
	{
		return _read_package(filename, false);
	}

	private Package _read_package(string filename, bool from_registry)
	{
		auto root = yaml.Loader(filename).load();

		Package p;

		p.id = root["id"].as!string;
		p.vers = root["version"].as!string;
		p.source = root["source"].as!string;

		if("deps" in root)
		{
			auto deps_list_unparsed = root["deps"];
			foreach(yaml.Node x; deps_list_unparsed)
			{
				Dependency d;

				if(x.isString)
				{
					auto s = x.as!string;
					auto toks = s.split("@");
					enforce(toks.length == 2, "invalid dependency: " ~ s);

					d.id = toks[0];
					d.vers_min = toks[1];
					d.vers_max = toks[1];
				}
				else if(x.isMapping)
				{
					d.id = x["id"].as!string;
					d.vers_min = x["version"].as!string;
					d.vers_max = x["version"].as!string;
				}
				else
				{
					throw new Exception("invalid dependency");
				}

				p.deps ~= d;
			}
		}

		foreach(yaml.Node x; root["build"])
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

	public override Package[] build_deps_list(Package p)
	{
		auto r = new Resolver(this);
		return r.resolve(p);
	}
}

private class Node
{
	PackageDesc pd;
	Node[] links;
	Node[] back_links;

	this(PackageDesc _pd)
	{
		pd = _pd;
	}
}

private class Resolver
{
	private Node[string] _finder;
	private bool[string] _marks; // actually set, value has no matter
	private Package[] _package_list;
	private IRegistry _registry;

	this(IRegistry r)
	{
		_registry = r;
	}

	Package[] resolve(Package p)
	{
		auto root = new Node(PackageDesc(p.id, "<building>"));

		_add_deps(root, p.deps);

		return _package_list;
	}

	void _add_deps(Node root, Dependency[] deps)
	{
		foreach(d; deps)
		{
			auto pd = PackageDesc(d.id, d.vers_max);
			auto p = _registry.read_package(pd);

			auto node = _finder.get(pd.id, null);
			bool already_existed = node !is null;

			if(node is null)
			{
				node = new Node(PackageDesc(d.id, d.vers_max));
				_finder[node.pd.id] = node;
			}
			else
			{
				if(node.pd.vers != pd.vers)
				{
					enforce(node.back_links.length > 0);
					enforce!SysExitEx("failed to build dependency list: package %s depends on %s but %s another version (%s) is required by %s".format(
							root.pd.fullname,
							pd.fullname,
							node.pd.id,
							node.pd.vers,
							node.back_links[0].pd.fullname,
						));
				}

				if(node.pd.id !in _marks)
				{
					throw new Exception("loop detected: %s requires %s but it is already in path".format(root.pd.fullname, pd.fullname));
				}
			}

			root.links ~= node;
			node.back_links ~= root;

			if(!already_existed)
			{
				_add_deps(node, p.deps);
				_package_list ~= p;
				_marks[p.id] = true;
			}
		}
	}
}

private class RegistryStub : IRegistry
{
	private Package[string] _packages;

	void update(){}
	void init(){}
	void add_package(Package p)
	{
		_packages[p.fullname] = p;
	}

	Package read_package(PackageDesc pd)
	{
		return _packages[pd.fullname];
	}

	Package read_package(string filename)
	{
		throw new Exception("Not Implemented");
	}

	Package[] build_deps_list(Package p)
	{
		throw new Exception("Not Implemented");
	}
}

private Package make_stub_package(string id, string vers)
{
	Package p;
	p.id = id;
	p.vers = vers;

	return p;
}

unittest
{
	auto r = new RegistryStub;


	Package p;
	Package root;

	p = make_stub_package("A", "1");
	p.deps ~= Dependency("B", "1");
	p.deps ~= Dependency("C", "1");
	r.add_package(p);
	root = p;

	p = make_stub_package("B", "1");
	p.deps ~= Dependency("C", "1");
	p.deps ~= Dependency("D", "1");
	r.add_package(p);

	p = make_stub_package("C", "1");
	p.deps ~= Dependency("D", "1");
	r.add_package(p);

	p = make_stub_package("D", "1");
	r.add_package(p);

	auto resolver = new Resolver(r);

	auto deps = resolver.resolve(root);

	//writefln("deps: %s", map!(x => x.fullname)(deps).array);
	assert(map!(x => x.fullname)(deps).array == ["D@1", "C@1", "B@1"]);
}

// loop
unittest
{
	auto r = new RegistryStub;


	Package p;
	Package root;

	p = make_stub_package("A", "1");
	p.deps ~= Dependency("B", "1");
	r.add_package(p);
	root = p;

	p = make_stub_package("B", "1");
	p.deps ~= Dependency("C", "1");
	r.add_package(p);

	p = make_stub_package("C", "1");
	p.deps ~= Dependency("B", "1");
	r.add_package(p);

	auto resolver = new Resolver(r);

	assertThrown(resolver.resolve(root));
}
