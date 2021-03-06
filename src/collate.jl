
# Turn a collection of markdown files into a browsable multi-page manual.

# Files to be weaved when generating a packages documentation.
const ext_doc_pat = r"\.(md|txt|rst)$"i


# Pattern for matching github package urls
const pkgurl_pat = r"github.com/(.*)\.git$"


# Generate documentation from the given package.
function collate(package::String; template::String="default")
    declarations = harvest(package)

    pkgver = ""
    try
        pkgver = Pkg.Dir.cd(() -> Pkg.Read.installed()[package][1])
    catch
    end
    pkgver_out = IOBuffer()
    print(pkgver_out, pkgver)
    pkgver = takebuf_string(pkgver_out)

    pkgurl = "#"
    try
        pkgurl_mat = match(pkgurl_pat, Pkg.Dir.cd(() -> Pkg.Read.url(package)))
        if pkgurl_mat != nothing
            pkgurl = string("http://github.com/", pkgurl_mat.captures[1])
        end
    catch
    end

    filenames = {}
    for filename in walkdir(joinpath(Pkg.dir(package), "doc"))
        if match(ext_doc_pat, filename) != nothing
            push!(filenames, filename)
        end
    end

    outdir = joinpath(Pkg.dir(package), "doc", "html")
    if !isdir(outdir)
        mkdir(outdir)
    end

    collate(filenames, template=template, outdir=outdir, pkgname=package,
            pkgver=pkgver, pkgurl=pkgurl, declarations=declarations)
end


# Generate documentation from multiple files.
function collate(filenames::Vector;
                 template::String="default",
                 outdir::String=".",
                 declarations::Dict=Dict(),
                 pkgname=nothing,
                 pkgver=nothing,
                 pkgurl=nothing,
                 pandocargs=nothing)
    toc = Dict()
    titles = Dict()

    declaration_markdown = generate_declaration_markdown(declarations)

    if !isdir(template)
        template = joinpath(Pkg.dir("Judo"), "templates", template)
        if !isdir(template)
            error("Can't find template $(template)")
        end
    end

    # make any expansions necessary in the original document
    docs = Dict()
    for filename in filenames
        name = choose_document_name(filename)
        docs[name] = expand_declaration_docs(readall(filename),
                                             declaration_markdown)
    end

    # dry-run to collect the section names in each document
    for (name, doc) in docs
        metadata, sections = weave(IOBuffer(doc), IOBuffer(), dryrun=true)
        title = get(metadata, "title", name)
        titles[name] = title
        part = get(metadata, "part", nothing)
        if !haskey(toc, part)
            toc[part] = {}
        end

        push!(toc[part], (get(metadata, "order", 0), name, title, sections))
    end
    for part_content in values(toc)
        sort!(part_content)
    end

    pandoc_template = joinpath(template, "template.html")

    keyvals = Dict()

    if pkgname != nothing
        keyvals["pkgname"] = pkgname
    end

    if pkgver != nothing
        keyvals["pkgver"] = pkgver
    end

    if pkgurl != nothing
        keyvals["pkgurl"] = pkgurl
    end

    for (name, doc) in docs
        println(STDERR, "weaving ", name)
        fmt = :markdown
        title = titles[name]
        outfilename = joinpath(outdir, string(name, ".html"))
        outfile = open(outfilename, "w")
        keyvals["table-of-contents"] = table_of_contents(toc, title)
        metadata, sections = weave(IOBuffer(doc), outfile,
                                   name=name, template=pandoc_template,
                                   toc=true, outdir=outdir,
                                   keyvals=keyvals,
                                   pandocargs=pandocargs)
        close(outfile)
    end

    # copy template files
    run(`cp -r $(joinpath(template, "js")) $(outdir)`)
    run(`cp -r $(joinpath(template, "css")) $(outdir)`)
end


# pattern for choosing document names
const fileext_pat = r"^(.+)\.([^\.]+)$"


# Choose a documents name from its file name.
function choose_document_name(filename::String)
    filename = basename(filename)
    mat = match(fileext_pat, filename)
    name = filename
    if !is(mat, nothing)
        name = mat.captures[1]
        if mat.captures[2] == "md"
            fmt = :markdown
        elseif mat.captures[2] == "rst"
            fmt = :rst
        elseif mat.captures[2] == "tex"
            fmt = :latex
        elseif mat.captures[2] == "html" || mat.captures[2] == "htm"
            fmt = :html
        else
            name = filename
        end
    end

    name
end


# TODO: It would be better if I can make this one <ul>, that way I could use
# List.js. How can I retain roughly the same style though.

# Generate a table of contents for the given document.
function table_of_contents(toc, selected_title::String)
    parts = collect(keys(toc))
    part_order = [minimum([order for (order, name, title, sections) in toc[part]])
                  for part in parts]

    out = IOBuffer()
    write(out, "<ul class=\"toc list\">")
    for part in parts[sortperm(part_order)]
        if part != nothing
            write(out,
                """
                <li>
                    <hr><div class="toc-part">$(part)</div>
                </li>
                """)
        end

        for (order, name, title, sections) in toc[part]
            classes = title == selected_title ?
                "toc-item toc-current-doc" : "toc-item"

            write(out,
                """
                <li>
                    <div class="$(classes)"><a href="$(name).html">$(title)</a></div>
                </li>
                """)

                write(out, table_of_contents_sections(name, sections))
        end
    end
    write(out, "</ul>")
    takebuf_string(out)
end


function table_of_contents_sections(parent, sections; maxlevel=2)
    if isempty(sections)
        return ""
    end

    out = IOBuffer()
    current_level = 0
    for (level, section) in sections
        if level > maxlevel
            continue
        end

        while level > current_level
            current_level += 1
        end

        while level < current_level
            current_level -= 1
        end

        write(out,
            """
            <li>
                <div style="margin-left: $(level)em" class="toc-item"><a href=\"$(parent).html#$(section_id(section))\">$(section)</div></a/>
            </li>
            """)
    end
    return takebuf_string(out)
end


# Turn a section name into an html id.
function section_id(section::String)
    lowercase(replace(section, r"[\s\/\?]+", "-"))
end

