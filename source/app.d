import std.array;
import std.exception;
import std.path;
import std.process;
import std.stdio;
import std.string;
import std.regex;
import docopt;
import registry;
import console;
import mustache;
import exception;
import url;

alias MustacheEngine!(string) Mustache;

struct SpecialVars
{
	string[] include_dirs;
	string[] lib_dirs;
	string dest_dir;
}

class LocalPackages
{
	public this(Registry r)
	{
		_registry = r;
	}

	public void install(Package p)
	{
		if(std.file.exists(_pkg_install_file(p)))
		{
			Console.dim("skipping installing package %s: already installed".format(p.fullname));
			return;
		}

		_download(p);
		_build(p);

		auto install_file = _pkg_install_file(p);
		new File(install_file, "w").close(); //touch

		Console.bold("installed package " ~ p.fullname);
	}

	private string _pkg_install_file(Package p)
	{
		return buildPath(p.pkg_dir, "installed");
	}

	public void build(Package p)
	{
		_build(p);
	}

	private void _download(Package p)
	{
		enforce(p.from_registry, "no need to download packages not from registry");

		if(std.file.exists(p.pkg_dir))
		{
			Console.dim("skipping fetching package %s: already in cache".format(p.fullname));
			return;
		}
		Console.dim("fetching package " ~ p.fullname);

		std.file.mkdirRecurse(p.pkg_dir);
		std.file.mkdirRecurse(p.dest_dir);

		auto urlparts = urlsplit(p.source);

		if(urlparts.scheme == "git")
		{
			auto r = execute(["git",
				"clone",
				p.source,
				p.src_dir,
			]);

			enforce(r.status == 0, "failed to fetch package %s src:\n%s".format(p.fullname, r.output));
		}
		else if(urlparts.scheme == "local")
		{
			auto r = execute(["cp", "-r", urlparts.location, p.src_dir]);

			enforce!SysExitEx(r.status == 0, "failed to fetch %s".format(p.fullname));
		}
		else
		{
			throw new SysExitEx("unknown source type for pkg %s source %s".format(p.fullname, p.source));
		}

		Console.bold("fetched package " ~ p.fullname);
	}

	private void _build(Package p)
	{
		auto deps = _registry.build_deps_list(p);

		auto spec_vars = SpecialVars();
		spec_vars.dest_dir = p.dest_dir();

		foreach(d; deps)
		{
			SpecialVars dsv;
			dsv.dest_dir = d.dest_dir();

			spec_vars.include_dirs ~= _subst(d.include_export, dsv);
			spec_vars.lib_dirs ~= _subst(d.libs_export, dsv);
		}

		foreach(s; p.build_script)
		{
			auto cmd = _subst(s, spec_vars);

			Console.dim("executing: %s".format(cmd));

			auto r = executeShell(cmd, null, Config.none, size_t.max, p.src_dir());

			enforce(r.status == 0, "failed to install dependency %s:\n%s".format(p.fullname(), r.output));
		}
	}

	private string _subst(string s, SpecialVars sv)
	{
		Mustache mustache;

    	auto ctx = new Mustache.Context;

    	_subst_add_subctx("INCLUDE_DIRS", sv.include_dirs, ctx);
    	_subst_add_subctx("LIB_DIRS", sv.lib_dirs, ctx);
    	ctx["DESTDIR"] = sv.dest_dir;

    	return mustache.renderString(s, ctx);
	}

	private void _subst_add_subctx(string name, string[] strs, Mustache.Context ctx)
	{
		foreach(s; strs)
		{
			auto sub = ctx.addSubContext(name);

			sub["x"] = s;
		}
	}


	private Registry _registry;
}

class App
{
	this()
	{
		_registry = new Registry;
		_local_packages = new LocalPackages(_registry);
	}

	public void run(string[] args)
	{
		parse_args(args);

		if(_args["update"].isTrue)
		{
			_registry.update();
		}
		else if(_args["push"].isTrue)
		{
			_push();
		}
		else if(_args["build"].isTrue)
		{
			_build();
		}
	}

	private void parse_args(string[] args)
	{
		auto doc = "cdist  - c dependency manager

    Usage:
      cdist build
      cdist update
      cdist push [--local]
      cdist -h | --help
      cdist --version

    Options:
      -h --help     Show this screen.
      --version     Show version.
      --local       Add to registy as local dependency.
    ";

	    _args = docopt.docopt(doc, args[1..$], true, "dev");
	}

	private void _push()
	{
		_registry.init();

		if(!std.file.exists("cdist.yaml"))
		{
			throw new SysExitEx("there is no cdist.yaml");
		}

		string path;

		auto p = _registry.read_package("cdist.yaml");
		if(p.source.startsWith("."))
		{
			path = _get_package_path(p);
		}
		else
		{
			path = p.source;
		}

		p.source = path;

		_registry.add_package(p);
	}

	private string _get_package_path(Package p)
	{
		string path;

		if(_args["--local"].isTrue)
		{
			path = "local://" ~ buildPath(std.file.getcwd(), p.source);
		}
		else
		{
			// need to think is it a good way or not
			auto r = execute(["git", "remote", "-v"]);
			enforceEx!SysExitEx(r.status == 0, "failed to execute git remote -v:\n" ~ r.output);


			auto re = regex(r"origin\s+([^ ]+)\s+\(fetch\)");

			auto lines = r.output.splitLines();
			foreach(l; lines)
			{
				auto m = matchAll(l, re);
				if(!m.empty)
				{
					path = "git://" ~ m.captures[1];
				}
			}

			r = execute(["git", "log", "--format=%H"]);
			enforceEx!SysExitEx(r.status == 0, "failed to execute git log:\n" ~ r.output);

			path ~= "#" ~ r.output.strip();
		}

		enforce!SysExitEx(path != null, "failed to find origin");

		return path;
	}

	private void _build()
	{
		_registry.init();

		auto p = _registry.read_package("cdist.yaml");

		auto deps_list = _registry.build_deps_list(p); // topologically sorted

		foreach_reverse(d; deps_list)
		{
			_local_packages.install(d);
		}

		_local_packages.build(p);
	}

	private docopt.ArgValue[string] _args;
	private Registry _registry;
	private LocalPackages _local_packages;
}

void main(string[] args)
{
	auto app = new App;

	try
	{
		app.run(args);
	}
	catch(SysExitEx e)
	{
		Console.red(e.msg);
	}
	catch(Exception e)
	{
		Console.red(e.toString());
	}
}
