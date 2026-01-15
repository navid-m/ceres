import std.stdio;
import std.file;
import std.path;
import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.regex;
import std.json;
import std.format;

/** 
 * A function documentation.
 */
struct FunctionDoc
{
    string name;
    string returnType;
    string[] parameters;
    string[] comments;
    size_t lineNumber;
}

/** 
 * Some documentation about a class.
 */
struct ClassDoc
{
    string name;
    string type;
    string[] comments;
    FunctionDoc[] methods;
    string[] fields;
    size_t lineNumber;
}

struct ModuleDoc
{
    string name;
    string filepath;
    string[] comments;
    FunctionDoc[] functions;
    ClassDoc[] classes;
    string[] imports;
}

class Parser
{
    private string content;
    private string[] lines;
    private size_t currentLine;

    this(string content)
    {
        this.content = content;
        this.lines = content.split("\n");
        this.currentLine = 0;
    }

    ModuleDoc parse(string filepath)
    {
        ModuleDoc doc;
        doc.filepath = filepath;
        doc.name = extractModuleName(filepath);

        string[] pendingComments;

        for (currentLine = 0; currentLine < lines.length; currentLine++)
        {
            string line = lines[currentLine].strip();

            if (line.startsWith("///") || line.startsWith("/**") || line.startsWith("/*"))
            {
                pendingComments ~= extractComment(line);
                if (line.startsWith("/**") || line.startsWith("/*"))
                {
                    while (currentLine < lines.length && !lines[currentLine].strip().endsWith("*/"))
                    {
                        currentLine++;
                        if (currentLine < lines.length)
                        {
                            string commentLine = lines[currentLine].strip();
                            if (commentLine != "*/")
                                pendingComments ~= extractComment(commentLine);
                        }
                    }
                }
            }
            else if (line.startsWith("module "))
                doc.name = extractModuleDeclaration(line);
            else if (line.startsWith("import "))
                doc.imports ~= line;
            else if (line.length > 0 && !line.startsWith("//"))
            {
                if (line.startsWith("class ") || line.startsWith("struct ")
                        || line.startsWith("interface ") || line.startsWith("enum "))
                {
                    auto classDoc = parseClass(line, pendingComments);
                    if (classDoc.name.length > 0)
                        doc.classes ~= classDoc;
                    pendingComments = [];
                }
                else if (isFunction(line))
                {
                    auto funcDoc = parseFunction(line, pendingComments);
                    if (funcDoc.name.length > 0)
                        doc.functions ~= funcDoc;
                    pendingComments = [];
                }
                else if (!line.startsWith("{") && !line.startsWith("}"))
                    pendingComments = [];
            }
        }

        return doc;
    }

    private string extractComment(string line)
    {
        if (line.startsWith("///"))
        {
            return line[3 .. $].strip();
        }
        else if (line.startsWith("/**"))
        {
            string cleaned = line[3 .. $];
            if (cleaned.endsWith("*/"))
            {
                cleaned = cleaned[0 .. $ - 2];
            }
            return cleaned.strip();
        }
        else if (line.startsWith("/*"))
        {
            string cleaned = line[2 .. $];
            if (cleaned.endsWith("*/"))
            {
                cleaned = cleaned[0 .. $ - 2];
            }
            return cleaned.strip();
        }
        else if (line.startsWith("*"))
        {
            return line[1 .. $].strip();
        }
        return line.strip();
    }

    private string extractModuleName(string filepath) => baseName(filepath, ".d");

    private string extractModuleDeclaration(string line)
    {
        auto parts = line.split();
        if (parts.length >= 2)
        {
            string moduleName = parts[1];
            if (moduleName.endsWith(";"))
            {
                moduleName = moduleName[0 .. $ - 1];
            }
            return moduleName;
        }
        return "";
    }

    private bool isFunction(string line)
    {
        if (line.indexOf("(") == -1 || line.indexOf(")") == -1)
            return false;

        string trimmed = line.strip();

        if (trimmed.startsWith("if") || trimmed.startsWith("while")
                || trimmed.startsWith("for") || trimmed.startsWith("switch") || trimmed.startsWith("foreach")
                || trimmed.startsWith("return")
                || trimmed.startsWith("assert") || trimmed.startsWith("else"))
        {
            return false;
        }

        if (trimmed.indexOf("=") != -1 && trimmed.indexOf("=") < trimmed.indexOf("("))
            return false;

        auto parenPos = trimmed.indexOf("(");
        if (parenPos > 0)
        {
            auto beforeParen = trimmed[0 .. parenPos].strip();

            if (beforeParen.indexOf(".") != -1)
                return false;

            auto words = beforeParen.split();
            if (words.length < 2)
            {
                return false;
            }

            string firstWord = words[0];
            bool hasModifierOrType = false;

            if (firstWord == "public" || firstWord == "private"
                    || firstWord == "protected" || firstWord == "static" || firstWord == "final"
                    || firstWord == "override" || firstWord == "abstract"
                    || firstWord == "const" || firstWord == "immutable" || firstWord == "shared"
                    || firstWord == "pure" || firstWord == "nothrow" || firstWord == "@safe"
                    || firstWord == "@trusted" || firstWord == "@system"
                    || firstWord == "void" || firstWord == "int" || firstWord == "bool"
                    || firstWord == "string" || firstWord == "char"
                    || firstWord == "byte" || firstWord == "short" || firstWord == "long" || firstWord == "float"
                    || firstWord == "double" || firstWord == "real" || firstWord == "auto")
            {
                hasModifierOrType = true;
            }

            if (words.length >= 2 && words[0] != "auto")
            {
                string secondWord = words[1];
                if (secondWord.indexOf("(") == -1 && (secondWord[0] >= 'a'
                        && secondWord[0] <= 'z' || secondWord[0] >= 'A' && secondWord[0] <= 'Z'))
                {
                    hasModifierOrType = true;
                }
            }

            return hasModifierOrType;
        }

        return false;
    }

    private FunctionDoc parseFunction(string line, string[] comments)
    {
        FunctionDoc doc;
        doc.comments = comments;
        doc.lineNumber = currentLine + 1;

        auto parenPos = line.indexOf("(");
        auto closeParenPos = line.indexOf(")");

        if (parenPos == -1 || closeParenPos == -1)
        {
            return doc;
        }

        auto beforeParen = line[0 .. parenPos].strip().split();
        if (beforeParen.length >= 1)
        {
            doc.name = beforeParen[$ - 1];

            if (beforeParen.length >= 2)
            {
                doc.returnType = beforeParen[0 .. $ - 1].join(" ");
            }
            else
            {
                doc.returnType = "void";
            }
        }

        auto paramsStr = line[parenPos + 1 .. closeParenPos].strip();
        if (paramsStr.length > 0)
        {
            doc.parameters = paramsStr.split(",").map!(p => p.strip()).array;
        }

        return doc;
    }

    private ClassDoc parseClass(string line, string[] comments)
    {
        ClassDoc doc;
        doc.comments = comments;
        doc.lineNumber = currentLine + 1;

        auto parts = line.split();
        if (parts.length >= 2)
        {
            doc.type = parts[0];
            doc.name = parts[1];

            if (doc.name.indexOf("{") != -1)
            {
                doc.name = doc.name[0 .. doc.name.indexOf("{")].strip();
            }
            if (doc.name.indexOf(":") != -1)
            {
                doc.name = doc.name[0 .. doc.name.indexOf(":")].strip();
            }
        }

        return doc;
    }
}

class HTMLGenerator
{
    private ModuleDoc[] modules;
    private string outputDir;

    this(ModuleDoc[] modules, string outputDir)
    {
        this.modules = modules;
        this.outputDir = outputDir;
    }

    void generate()
    {
        if (!exists(outputDir))
        {
            mkdirRecurse(outputDir);
        }

        generateIndex();

        foreach (mod; modules)
        {
            generateModulePage(mod);
        }

        generateCSS();
    }

    private void generateIndex()
    {
        auto f = File(buildPath(outputDir, "index.html"), "w");
        string templateContent = import("index_template.html");

        auto listContent = appender!string;

        foreach (mod; modules)
        {
            listContent.put(format("                    <li><a href=\"%s.html\">%s</a></li>\n",
                    sanitizeFilename(mod.name), escapeHTML(mod.name)));
        }

        string output = templateContent.replace("{{modules_list}}", listContent.data);
        f.write(output);
        f.close();
    }

    private void generateModulePage(ModuleDoc mod)
    {
        auto filename = buildPath(outputDir, sanitizeFilename(mod.name) ~ ".html");
        auto f = File(filename, "w");
        string templateContent = import("module_template.html");

        auto content = appender!string;

        if (mod.comments.length > 0)
        {
            content.put("<section class=\"module-description\">\n");
            foreach (comment; mod.comments)
            {
                content.put(format("<p>%s</p>\n", escapeHTML(comment)));
            }
            content.put("</section>\n");
        }

        if (mod.classes.length > 0)
        {
            content.put("<section class=\"classes\">\n");
            content.put("<h2>Classes and Structures</h2>\n");

            foreach (cls; mod.classes)
            {
                content.put("<div class=\"class-doc\">\n");
                content.put(format("<h3>%s %s</h3>\n", escapeHTML(cls.type), escapeHTML(cls.name)));

                if (cls.comments.length > 0)
                {
                    content.put("<div class=\"description\">\n");
                    foreach (comment; cls.comments)
                    {
                        content.put(format("<p>%s</p>\n", escapeHTML(comment)));
                    }
                    content.put("</div>\n");
                }

                content.put("</div>\n");
            }

            content.put("</section>\n");
        }

        if (mod.functions.length > 0)
        {
            content.put("<section class=\"functions\">\n");
            content.put("<h2>Functions</h2>\n");

            foreach (func; mod.functions)
            {
                content.put("<div class=\"function-doc\">\n");
                content.put("<div class=\"signature\">\n");
                content.put(format("<span class=\"return-type\">%s</span> \n",
                        escapeHTML(func.returnType)));
                content.put(format("<span class=\"function-name\">%s</span>",
                        escapeHTML(func.name)));
                content.put("<span class=\"parameters\">(");

                foreach (i, param; func.parameters)
                {
                    if (i > 0)
                        content.put(", ");
                    content.put(escapeHTML(param));
                }

                content.put(")</span>\n");
                content.put("</div>\n");

                if (func.comments.length > 0)
                {
                    content.put("<div class=\"description\">\n");
                    foreach (comment; func.comments)
                    {
                        content.put(format("<p>%s</p>\n", escapeHTML(comment)));
                    }
                    content.put("</div>\n");
                }

                content.put("</div>\n");
            }

            content.put("</section>\n");
        }

        string output = templateContent.replace("{{module_name}}", escapeHTML(mod.name));
        output = output.replace("{{content}}", content.data);

        f.write(output);
        f.close();
    }

    private void generateCSS()
    {
        auto f = File(buildPath(outputDir, "style.css"), "w");
        string cssContent = import("style.css");
        f.write(cssContent);
        f.close();
    }

    private string escapeHTML(string text)
    {
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">",
                "&gt;").replace("\"", "&quot;").replace("'", "&#39;");
    }

    private string sanitizeFilename(string name)
    {
        return name.replace(".", "_").replace("/", "_").replace("\\", "_");
    }
}

struct ProjectInfo
{
    bool isDubProject;
    string projectName;
    string[] sourceDirectories;
}

ProjectInfo detectProject(string path)
{
    ProjectInfo info;
    info.isDubProject = false;
    info.sourceDirectories = ["source", "src"];

    string dubJsonPath = buildPath(path, "dub.json");
    string dubSdlPath = buildPath(path, "dub.sdl");

    if (exists(dubJsonPath))
    {
        info.isDubProject = true;
        try
        {
            string jsonContent = readText(dubJsonPath);
            JSONValue json = parseJSON(jsonContent);

            if ("name" in json)
            {
                info.projectName = json["name"].str;
            }

            if ("sourcePaths" in json)
            {
                info.sourceDirectories = [];
                if (json["sourcePaths"].type == JSONType.array)
                {
                    foreach (ipath; json["sourcePaths"].array)
                    {
                        info.sourceDirectories ~= ipath.str;
                    }
                }
            }
        }
        catch (Exception e)
        {
            writeln("Warning: Failed to parse dub.json");
        }
    }
    else if (exists(dubSdlPath))
    {
        info.isDubProject = true;
        try
        {
            string sdlContent = readText(dubSdlPath);
            foreach (line; sdlContent.split("\n"))
            {
                string trimmed = line.strip();
                if (trimmed.startsWith("name "))
                {
                    auto parts = trimmed.split();
                    if (parts.length >= 2)
                    {
                        info.projectName = parts[1].strip("\"");
                    }
                }
            }
        }
        catch (Exception e)
        {
            writeln("Warning: Failed to parse dub.sdl");
        }
    }

    return info;
}

string[] findDFiles(string rootPath)
{
    string[] files;

    if (isFile(rootPath) && rootPath.endsWith(".d"))
    {
        return [rootPath];
    }

    if (!isDir(rootPath))
    {
        return files;
    }

    void scanDirectory(string dir)
    {
        foreach (entry; dirEntries(dir, SpanMode.shallow))
        {
            if (entry.isDir)
            {
                string dirName = baseName(entry.name);
                if (dirName != ".dub" && dirName != "docs" && !dirName.startsWith("."))
                {
                    scanDirectory(entry.name);
                }
            }
            else if (entry.isFile && entry.name.endsWith(".d"))
            {
                files ~= entry.name;
            }
        }
    }

    scanDirectory(rootPath);
    return files;
}

void main(string[] args)
{
    string targetPath = ".";

    if (args.length > 1)
    {
        targetPath = args[1];
    }

    if (!exists(targetPath))
    {
        stderr.writeln("Error: Path does not exist: ", targetPath);
        return;
    }

    string[] dFiles;
    ProjectInfo projectInfo;

    if (isFile(targetPath) && targetPath.endsWith(".d"))
    {
        dFiles = [targetPath];
        writeln("Documenting single file: ", targetPath);
    }
    else if (isDir(targetPath))
    {
        projectInfo = detectProject(targetPath);

        if (projectInfo.isDubProject)
        {
            writeln("Detected dub project");
            if (projectInfo.projectName.length > 0)
            {
                writeln("Project name: ", projectInfo.projectName);
            }

            foreach (srcDir; projectInfo.sourceDirectories)
            {
                string fullPath = buildPath(targetPath, srcDir);
                if (exists(fullPath))
                {
                    dFiles ~= findDFiles(fullPath);
                }
            }
        }
        else
        {
            writeln("Warning: No dub.json or dub.sdl found, scanning for .d files");
            dFiles = findDFiles(targetPath);
        }

        if (dFiles.length == 0)
        {
            stderr.writeln("Error: No .d files found in ", targetPath);
            return;
        }
    }

    writeln("Found ", dFiles.length, " D file(s)");

    ModuleDoc[] modules;

    foreach (file; dFiles)
    {
        try
        {
            writeln("Parsing: ", file);
            string content = readText(file);
            auto parser = new Parser(content);
            auto moduleDoc = parser.parse(file);
            modules ~= moduleDoc;
        }
        catch (Exception e)
        {
            stderr.writeln("Error parsing ", file, ": ", e.msg);
        }
    }

    string outputDir = "docs";
    writeln("Generating documentation in ./", outputDir);

    auto generator = new HTMLGenerator(modules, outputDir);
    generator.generate();

    writeln("Documentation generated successfully.");
    writeln("Open ", buildPath(outputDir, "index.html"), " to view");
}
