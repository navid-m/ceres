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
    bool isPrivate;
}

/**
 * A field documentation.
 */
struct FieldDoc
{
    string declaration;
    string[] comments;
    size_t lineNumber;
    bool isPrivate;
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
    FieldDoc[] fields;
    size_t lineNumber;
}

/**
 * A enum member documentation.
 */
struct EnumMemberDoc
{
    string name;
    string value;
    string[] comments;
    size_t lineNumber;
}

/**
 * Some documentation about an enum.
 */
struct EnumDoc
{
    string name;
    string[] comments;
    EnumMemberDoc[] members;
    size_t lineNumber;
}

/**
 * Some documentation about a module.
 */
struct ModuleDoc
{
    string name;
    string filepath;
    string[] comments;
    FunctionDoc[] functions;
    ClassDoc[] classes;
    EnumDoc[] enums;
    string[] imports;
}

/**
 * Parser for Dlang files.
 */
class Parser
{
    private string content;
    private string[] lines;
    private size_t currentLine;
    private string[] lastDocComment;

    /**
     * Construct a new parser instance
     *
     * Params:
     *   content = The content to parse
     */
    this(string content)
    {
        this.content = content;
        this.lines = content.split("\n");
        this.currentLine = 0;
    }

    /**
     * Parse a file into a ModuleDoc instance.
     *
     * Params:
     *   filepath = The path of the file
     *
     * Returns: The corresponding ModuleDoc instance
     */
    ModuleDoc parse(string filepath)
    {
        ModuleDoc doc;
        doc.filepath = filepath;
        doc.name = extractModuleName(filepath);

        string[] pendingComments;

        for (currentLine = 0; currentLine < lines.length; currentLine++)
        {
            string line = lines[currentLine].strip();

            if (line.strip() == "/// ditto")
            {
                pendingComments = lastDocComment.dup;
            }
            else if (line.startsWith("///") || line.startsWith("/**")
                    || line.startsWith("/*") || line.startsWith("/+") || line.startsWith("/++"))
            {
                pendingComments = [];
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
                else if (line.startsWith("/+") || line.startsWith("/++"))
                {
                    long nesting = 0;
                    nesting += line.count("/+");
                    nesting -= line.count("+/");

                    if (nesting > 0)
                    {
                        while (currentLine < lines.length)
                        {
                            currentLine++;
                            if (currentLine < lines.length)
                            {
                                string commentLine = lines[currentLine].strip();
                                nesting += commentLine.count("/+");
                                nesting -= commentLine.count("+/");

                                if (nesting > 0 || !commentLine.endsWith("+/"))
                                {
                                    pendingComments ~= extractComment(commentLine);
                                }
                                else if (commentLine.length > 2 && commentLine != "+/")
                                {
                                    pendingComments ~= extractComment(commentLine);
                                }

                                if (nesting <= 0)
                                    break;
                            }
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
                        || line.startsWith("interface "))
                {
                    auto classDoc = parseClass(line, pendingComments);
                    if (classDoc.name.length > 0)
                    {
                        doc.classes ~= classDoc;
                        if (pendingComments.length > 0)
                            lastDocComment = pendingComments.dup;
                    }
                    pendingComments = [];
                }
                else if (line.startsWith("enum "))
                {
                    auto enumDoc = parseEnum(line, pendingComments);
                    if (enumDoc.name.length > 0)
                    {
                        doc.enums ~= enumDoc;
                        if (pendingComments.length > 0)
                            lastDocComment = pendingComments.dup;
                    }
                    pendingComments = [];
                }
                else if (isFunction(line))
                {
                    auto funcDoc = parseFunction(line, pendingComments);
                    if (funcDoc.name.length > 0)
                    {
                        doc.functions ~= funcDoc;
                        if (pendingComments.length > 0)
                            lastDocComment = pendingComments.dup;
                    }
                    pendingComments = [];

                    long braceBalance = calculateBraceBalance(line);
                    if (braceBalance > 0 || line.indexOf("{") == -1)
                    {
                        if (line.strip().endsWith(";"))
                        {
                            // No body
                        }
                        else
                        {
                            bool sawBrace = line.indexOf("{") != -1;
                            while (currentLine < lines.length)
                            {
                                if (sawBrace && braceBalance == 0)
                                    break;

                                currentLine++;
                                if (currentLine >= lines.length)
                                    break;

                                string ln = lines[currentLine].strip();
                                long diff = calculateBraceBalance(ln);
                                if (ln.indexOf("{") != -1)
                                    sawBrace = true;

                                braceBalance += diff;
                            }
                        }
                    }
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
        else if (line.startsWith("/++"))
        {
            string cleaned = line[3 .. $];
            if (cleaned.endsWith("+/"))
            {
                cleaned = cleaned[0 .. $ - 2];
            }
            return cleaned.strip();
        }
        else if (line.startsWith("/+"))
        {
            string cleaned = line[2 .. $];
            if (cleaned.endsWith("+/"))
            {
                cleaned = cleaned[0 .. $ - 2];
            }
            return cleaned.strip();
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
        else if (line.startsWith("+"))
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

        if (trimmed.startsWith("this(") || trimmed.startsWith("~this(")
                || trimmed.startsWith("public this(") || trimmed.startsWith("private this(")
                || trimmed.startsWith("protected this("))
        {
            return true;
        }

        if (trimmed.startsWith("if") || trimmed.startsWith("while")
                || trimmed.startsWith("for") || trimmed.startsWith("switch") || trimmed.startsWith("foreach")
                || trimmed.startsWith("return") || trimmed.startsWith("assert") || trimmed.startsWith("else")
                || trimmed.startsWith("import ") || trimmed.startsWith("module ") || trimmed.startsWith("struct ")
                || trimmed.startsWith("class ") || trimmed.startsWith("interface ")
                || trimmed.startsWith("enum ") || trimmed.startsWith("union "))
        {
            return false;
        }

        if (trimmed.indexOf("=") != -1
                && trimmed.indexOf("=") < trimmed.indexOf("(") && !trimmed.startsWith("="))
            return false;

        if (trimmed.count("=") > 0 && trimmed.indexOf("=") < trimmed.indexOf("(")
                && !trimmed.startsWith("auto ") && !trimmed.startsWith("void ")
                && !trimmed.startsWith("int ") && !trimmed.startsWith("string ")
                && !trimmed.startsWith("bool ") && !trimmed.startsWith("float ")
                && !trimmed.startsWith("double ") && !trimmed.startsWith("char ")
                && !trimmed.startsWith("byte ") && !trimmed.startsWith("short ")
                && !trimmed.startsWith("long ") && !trimmed.startsWith("real "))
        {
            return false;
        }

        auto parenPos = findFuncParenIndex(trimmed);
        if (parenPos > 0)
        {
            auto beforeParen = trimmed[0 .. parenPos].strip();

            if (beforeParen.indexOf(".") != -1)
                return false;

            auto words = beforeParen.split();
            if (words.length == 0)
            {
                return false;
            }

            if (words.length >= 2)
            {
                string returnType = words[0];
                string funcName = words[1];

                string checkType = returnType;
                while (checkType.endsWith("[]"))
                    checkType = checkType[0 .. $ - 2];

                bool isFirstWordType = (checkType == "public" || checkType == "private"
                        || checkType == "protected" || checkType == "static"
                        || checkType == "final" || checkType == "override"
                        || checkType == "abstract" || checkType == "const"
                        || checkType == "immutable"
                        || checkType == "shared" || checkType == "pure" || checkType == "nothrow"
                        || checkType == "@safe" || checkType == "@trusted"
                        || checkType == "@system" || checkType == "void"
                        || checkType == "int" || checkType == "bool" || checkType == "string"
                        || checkType == "char" || checkType == "byte" || checkType == "short"
                        || checkType == "long" || checkType == "float"
                        || checkType == "double" || checkType == "real"
                        || checkType == "auto" || checkType.startsWith("@")); // Custom attributes

                if (isFirstWordType && isValidIdentifier(funcName))
                {
                    return true;
                }

                if (!isFirstWordType && isValidIdentifier(checkType))
                {
                    return true;
                }
            }
            else if (words.length == 1 && isValidIdentifier(words[0]))
            {
                return true;
            }
        }

        return false;
    }

    private bool isValidIdentifier(string ident)
    {
        if (ident.length == 0)
            return false;

        import std.algorithm;
        import std.range;

        if (!(ident[0] == '_' || (ident[0] >= 'a' && ident[0] <= 'z')
                || (ident[0] >= 'A' && ident[0] <= 'Z')))
            return false;

        foreach (ch; ident[1 .. $])
        {
            if (!(ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A'
                    && ch <= 'Z') || (ch >= '0' && ch <= '9')))
                return false;
        }

        return true;
    }

    private FunctionDoc parseFunction(string line, string[] comments)
    {
        FunctionDoc doc;
        doc.comments = comments;
        doc.lineNumber = currentLine + 1;

        string trimmed = line.strip();
        doc.isPrivate = trimmed.startsWith("private ") || trimmed.startsWith("private static ")
            || trimmed.startsWith("private final ") || trimmed.startsWith(
                    "private override ") || trimmed.startsWith("private abstract ")
            || trimmed.startsWith("private const ") || trimmed.startsWith(
                    "private immutable ") || trimmed.startsWith("private shared ")
            || trimmed.startsWith("private pure ") || trimmed.startsWith("private nothrow ")
            || (trimmed.startsWith("private") && !trimmed.startsWith("private("));

        auto parenPos = findFuncParenIndex(line);
        auto closeParenPos = -1;
        if (parenPos != -1)
            closeParenPos = cast(int) line.indexOf(")", parenPos);

        if (parenPos == -1 || closeParenPos == -1)
        {
            return doc;
        }

        auto beforeParen = line[0 .. parenPos].strip().split();

        if (trimmed.startsWith("this") || trimmed.indexOf(" this(") != -1)
        {
            doc.name = "this";
            doc.returnType = "";
        }
        else if (trimmed.startsWith("~this") || trimmed.indexOf(" ~this(") != -1)
        {
            doc.name = "~this";
            doc.returnType = "";
        }
        else if (beforeParen.length >= 1)
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

        try
        {
            if (line.length >= parenPos + 1 && line.length >= closeParenPos
                    && parenPos + 1 < closeParenPos)
            {
                auto paramsStr = line[parenPos + 1 .. closeParenPos].strip();
                if (paramsStr.length > 0)
                {
                    doc.parameters = paramsStr.split(",").map!(p => p.strip()).array;
                }
            }
        }
        catch (Exception e)
        {
            writeln("Error parsing parameters: ", e.msg);
        }

        return doc;
    }

    private long calculateBraceBalance(string line)
    {
        long balance = 0;
        bool inString = false;
        bool inChar = false;
        bool escape = false;

        for (size_t i = 0; i < line.length; i++)
        {
            char c = line[i];

            if (escape)
            {
                escape = false;
                continue;
            }

            if (c == '\\')
            {
                escape = true;
                continue;
            }
            if (inString)
            {
                if (c == '"')
                    inString = false;
            }
            else if (inChar)
            {
                if (c == '\'')
                    inChar = false;
            }
            else
            {
                if (c == '"')
                    inString = true;
                else if (c == '\'')
                    inChar = true;
                else if (c == '/' && i + 1 < line.length && line[i + 1] == '/')
                {
                    break;
                }
                else if (c == '{')
                    balance++;
                else if (c == '}')
                    balance--;
            }
        }
        return balance;
    }

    private EnumDoc parseEnum(string line, string[] comments)
    {
        EnumDoc doc;
        doc.comments = comments;
        doc.lineNumber = currentLine + 1;

        auto parts = line.split();
        if (parts.length >= 2)
        {
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

        long braceBalance = calculateBraceBalance(line);
        bool sawBrace = line.indexOf("{") != -1;

        string[] lastMemberDocComment;

        if (!sawBrace && line.strip().endsWith(";"))
            return doc;

        if (braceBalance > 0 || !sawBrace)
        {
            string[] memberComments;
            currentLine++;

            while (currentLine < lines.length)
            {
                string ln = lines[currentLine].strip();

                long diff = calculateBraceBalance(ln);

                if (diff > 0 || ln.indexOf("{") != -1)
                    sawBrace = true;

                braceBalance += diff;

                if (sawBrace && braceBalance == 0 && (diff < 0 || ln.indexOf("}") != -1))
                {
                    break;
                }

                if (sawBrace)
                {
                    if (ln.strip() == "/// ditto")
                    {
                        memberComments = lastMemberDocComment.dup;
                    }
                    else if (ln.startsWith("///") || ln.startsWith("/**")
                            || ln.startsWith("/*") || ln.startsWith("/+") || ln.startsWith("/++"))
                    {
                        memberComments = [];
                        memberComments ~= extractComment(ln);
                        if (ln.startsWith("/**") || ln.startsWith("/*"))
                        {
                            while (currentLine < lines.length
                                    && !lines[currentLine].strip().endsWith("*/"))
                            {
                                currentLine++;
                                if (currentLine < lines.length)
                                {
                                    string commentLine = lines[currentLine].strip();
                                    if (commentLine != "*/")
                                        memberComments ~= extractComment(commentLine);
                                }
                            }
                        }
                        else if (ln.startsWith("/+") || ln.startsWith("/++"))
                        {
                            long nesting = 0;
                            nesting += ln.count("/+");
                            nesting -= ln.count("+/");

                            if (nesting > 0)
                            {
                                while (currentLine < lines.length)
                                {
                                    currentLine++;
                                    if (currentLine < lines.length)
                                    {
                                        string commentLine = lines[currentLine].strip();
                                        nesting += commentLine.count("/+");
                                        nesting -= commentLine.count("+/");

                                        if (nesting > 0 || !commentLine.endsWith("+/"))
                                        {
                                            memberComments ~= extractComment(commentLine);
                                        }
                                        else if (commentLine.length > 2 && commentLine != "+/")
                                        {
                                            memberComments ~= extractComment(commentLine);
                                        }

                                        if (nesting <= 0)
                                            break;
                                    }
                                }
                            }
                        }
                    }
                    else if (ln.length > 0 && !ln.startsWith("//")
                            && !ln.startsWith("}") && !ln.startsWith("{"))
                    {
                        EnumMemberDoc member;
                        string memberDecl = ln;
                        if (memberDecl.endsWith(","))
                            memberDecl = memberDecl[0 .. $ - 1].strip();

                        auto eqIndex = memberDecl.indexOf("=");
                        if (eqIndex != -1)
                        {
                            member.name = memberDecl[0 .. eqIndex].strip();
                            member.value = memberDecl[eqIndex + 1 .. $].strip();
                        }
                        else
                        {
                            member.name = memberDecl;
                        }
                        member.comments = memberComments;
                        member.lineNumber = currentLine + 1;
                        doc.members ~= member;

                        if (memberComments.length > 0)
                            lastMemberDocComment = memberComments.dup;
                        memberComments = [];
                    }
                }
                currentLine++;
            }
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

        long braceBalance = calculateBraceBalance(line);
        bool sawBrace = line.indexOf("{") != -1;

        string[] lastMemberDocComment;

        if (!sawBrace && line.strip().endsWith(";"))
            return doc;

        if (braceBalance > 0 || !sawBrace)
        {
            string[] memberComments;
            currentLine++;

            while (currentLine < lines.length)
            {
                string ln = lines[currentLine].strip();

                long diff = calculateBraceBalance(ln);

                if (diff > 0 || ln.indexOf("{") != -1)
                    sawBrace = true;

                long oldBalance = braceBalance;
                braceBalance += diff;

                if (sawBrace && braceBalance == 0 && (diff < 0 || ln.indexOf("}") != -1))
                {
                    break;
                }

                if (sawBrace)
                {
                    if (ln.strip() == "/// ditto")
                    {
                        memberComments = lastMemberDocComment.dup;
                    }
                    else if (ln.startsWith("///") || ln.startsWith("/**")
                            || ln.startsWith("/*") || ln.startsWith("/+") || ln.startsWith("/++"))
                    {
                        memberComments = [];
                        memberComments ~= extractComment(ln);
                        if (ln.startsWith("/**") || ln.startsWith("/*"))
                        {
                            while (currentLine < lines.length
                                    && !lines[currentLine].strip().endsWith("*/"))
                            {
                                currentLine++;
                                if (currentLine < lines.length)
                                {
                                    string commentLine = lines[currentLine].strip();
                                    if (commentLine != "*/")
                                        memberComments ~= extractComment(commentLine);
                                }
                            }
                        }
                        else if (ln.startsWith("/+") || ln.startsWith("/++"))
                        {
                            long nesting = 0;
                            nesting += ln.count("/+");
                            nesting -= ln.count("+/");

                            if (nesting > 0)
                            {
                                while (currentLine < lines.length)
                                {
                                    currentLine++;
                                    if (currentLine < lines.length)
                                    {
                                        string commentLine = lines[currentLine].strip();
                                        nesting += commentLine.count("/+");
                                        nesting -= commentLine.count("+/");

                                        if (nesting > 0 || !commentLine.endsWith("+/"))
                                        {
                                            memberComments ~= extractComment(commentLine);
                                        }
                                        else if (commentLine.length > 2 && commentLine != "+/")
                                        {
                                            memberComments ~= extractComment(commentLine);
                                        }

                                        if (nesting <= 0)
                                            break;
                                    }
                                }
                            }
                        }
                    }
                    else if (isFunction(ln))
                    {
                        if (oldBalance == 1)
                        {
                            auto func = parseFunction(ln, memberComments);
                            if (func.name.length > 0)
                            {
                                doc.methods ~= func;
                                if (memberComments.length > 0)
                                    lastMemberDocComment = memberComments.dup;
                            }
                            memberComments = [];
                        }
                    }
                    else if (ln.startsWith("class ") || ln.startsWith("struct ")
                            || ln.startsWith("interface ") || ln.startsWith("enum "))
                    {
                        memberComments = [];
                        lastMemberDocComment = [];
                    }
                    else if (ln.length > 0 && !ln.startsWith("//")
                            && !ln.startsWith("}") && !ln.startsWith("{")
                            && braceBalance == 1 && ln.endsWith(";"))
                    {
                        FieldDoc fieldDoc;
                        fieldDoc.declaration = ln;
                        fieldDoc.comments = memberComments;
                        fieldDoc.lineNumber = currentLine + 1;
                        fieldDoc.isPrivate = ln.strip().startsWith("private ") || ln.strip()
                            .startsWith("private static ") || ln.strip().startsWith("private final ") || ln.strip()
                            .startsWith("private const ") || ln.strip().startsWith("private immutable ")
                            || ln.strip().startsWith("private shared ");
                        doc.fields ~= fieldDoc;
                        memberComments = [];
                        lastMemberDocComment = [];
                    }
                }
                currentLine++;
            }
        }

        return doc;
    }

    private ptrdiff_t findFuncParenIndex(string str)
    {
        auto firstParen = str.indexOf("(");
        if (firstParen == -1)
            return -1;

        auto externPos = str.indexOf("extern");
        if (externPos != -1 && externPos < firstParen)
        {
            auto between = str[externPos + 6 .. firstParen].strip();
            if (between.length == 0)
            {
                auto closeParen = str.indexOf(")", firstParen);
                if (closeParen != -1)
                {
                    return str.indexOf("(", closeParen);
                }
            }
        }
        return firstParen;
    }
}

class HTMLGenerator
{
    private ModuleDoc[] modules;
    private string outputDir;
    private string projectName;
    private string licenseType;
    private string[string] typeLinks;

    this(ModuleDoc[] modules, string outputDir, string projectName, string licenseType = "")
    {
        this.modules = modules;
        this.outputDir = outputDir;
        this.projectName = projectName.length > 0 ? projectName : "Project";
        this.licenseType = licenseType;
        buildTypeLinks();
    }

    private void buildTypeLinks()
    {
        typeLinks["string"] = "https://dlang.org/phobos/std_string.html";
        typeLinks["int"] = "https://dlang.org/spec/type.html#int";
        typeLinks["bool"] = "https://dlang.org/spec/type.html#bool";
        typeLinks["void"] = "https://dlang.org/spec/type.html#void";
        typeLinks["float"] = "https://dlang.org/spec/type.html#float";
        typeLinks["double"] = "https://dlang.org/spec/type.html#double";
        typeLinks["size_t"] = "https://dlang.org/spec/type.html#size_t";
        typeLinks["Object"] = "https://dlang.org/spec/type.html#Object";

        foreach (mod; modules)
        {
            foreach (cls; mod.classes)
            {
                typeLinks[cls.name] = format("%s.html#%s", sanitizeFilename(mod.name), cls.name);
            }
            foreach (en; mod.enums)
            {
                typeLinks[en.name] = format("%s.html#%s", sanitizeFilename(mod.name), en.name);
            }
        }
    }

    private string linkify(string code)
    {
        auto re = regex(`\b\w+\b`);
        auto app = appender!string;
        size_t lastPos = 0;

        foreach (m; code.matchAll(re))
        {
            app.put(escapeHTML(code[lastPos .. m.pre.length]));
            string word = m.hit;
            if (word in typeLinks)
            {
                app.put(format("<a href=\"%s\" class=\"text-blue-400 hover:text-blue-300 transition-colors\">%s</a>",
                        typeLinks[word], escapeHTML(word)));
            }
            else
            {
                app.put(escapeHTML(word));
            }
            lastPos = m.pre.length + word.length;
        }
        app.put(escapeHTML(code[lastPos .. $]));
        return app.data;
    }

    void generate()
    {
        if (!exists(outputDir))
        {
            mkdirRecurse(outputDir);
        }

        generateIndex();
        generateSearchIndex();

        foreach (mod; modules)
        {
            generateModulePage(mod);
        }
    }

    private void generateSearchIndex()
    {
        JSONValue[] items;

        foreach (mod; modules)
        {
            string modFile = sanitizeFilename(mod.name) ~ ".html";

            JSONValue modItem;
            modItem["name"] = JSONValue(mod.name);
            modItem["type"] = JSONValue("module");
            modItem["link"] = JSONValue(modFile);
            items ~= modItem;

            foreach (cls; mod.classes)
            {
                string link = modFile ~ "#" ~ cls.name;
                JSONValue clsItem;
                clsItem["name"] = JSONValue(cls.name);
                clsItem["type"] = JSONValue(cls.type);
                clsItem["link"] = JSONValue(link);
                clsItem["module"] = JSONValue(mod.name);
                items ~= clsItem;

                foreach (method; cls.methods)
                {
                    string methodId = cls.name ~ "." ~ method.name;
                    string mLink = modFile ~ "#" ~ methodId;
                    JSONValue mItem;
                    mItem["name"] = JSONValue(method.name);
                    mItem["type"] = JSONValue("method");
                    mItem["parent"] = JSONValue(cls.name);
                    mItem["link"] = JSONValue(mLink);
                    mItem["module"] = JSONValue(mod.name);
                    items ~= mItem;
                }
            }

            foreach (func; mod.functions)
            {
                string fLink = modFile ~ "#" ~ func.name;
                JSONValue fItem;
                fItem["name"] = JSONValue(func.name);
                fItem["type"] = JSONValue("function");
                fItem["link"] = JSONValue(fLink);
                fItem["module"] = JSONValue(mod.name);
                items ~= fItem;
            }
        }

        auto f = File(buildPath(outputDir, "search_index.js"), "w");
        f.write("const searchIndex = " ~ JSONValue(items).toString() ~ ";");
        f.close();
    }

    private void generateIndex()
    {
        auto f = File(buildPath(outputDir, "index.html"), "w");
        string templateContent = import("index_template.html");

        auto listContent = appender!string;

        foreach (mod; modules)
        {
            listContent.put(format("<li><a href=\"%s.html\" class=\"block p-4 bg-gray-800/50 hover:bg-gray-700/50 rounded-lg border border-border-color hover:border-blue-500 transition-all duration-200 group\">\n",
                    sanitizeFilename(mod.name)));
            listContent.put(format("<div class=\"flex items-center justify-between\">\n"));
            listContent.put(format("<span class=\"text-blue-400 group-hover:text-blue-300 font-medium\">%s</span>\n",
                    escapeHTML(mod.name)));
            listContent.put(format("<svg class=\"w-5 h-5 text-gray-600 group-hover:text-blue-400 transform group-hover:translate-x-1 transition-transform\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\">\n"));
            listContent.put(format("<path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M9 5l7 7-7 7\"></path>\n"));
            listContent.put(format("</svg>\n"));
            listContent.put(format("</div>\n"));
            listContent.put(format("</a></li>\n"));
        }

        string output = templateContent.replace("{{modules_list}}", listContent.data);
        output = output.replace("{{project_name}}", escapeHTML(projectName));

        string licenseInfo = "";
        if (licenseType.length > 0)
        {
            licenseInfo = escapeHTML(licenseType);
        }
        output = output.replace("{{license_info}}", licenseInfo);

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
            content.put(
                    "<section class=\"bg-card-bg rounded-xl p-6 shadow-lg border border-border-color\">\n");
            content.put("<div class=\"prose prose-invert max-w-none\">\n");
            content.put(formatComment(mod.comments));
            content.put("</div>\n");
            content.put("</section>\n");
        }

        if (mod.classes.length > 0)
        {
            content.put(
                    "<section class=\"bg-card-bg rounded-xl shadow-lg border border-border-color overflow-hidden\">\n");
            content.put("<div class=\"p-6 space-y-6\">\n");

            foreach (cls; mod.classes)
            {
                content.put("<div class=\"bg-gray-800/40 rounded-lg p-6 border border-border-color hover:border-red-500/50 transition-colors\">\n");
                content.put(format(
                        "<h3 id=\"%s\" class=\"text-xl font-semibold text-cyan-400 mb-3 flex items-center gap-2\">\n",
                        escapeHTML(cls.name)));
                content.put("<span class=\"text-gray-500 text-sm font-normal uppercase tracking-wide\">" ~ escapeHTML(
                        cls.type) ~ "</span>\n");
                content.put(escapeHTML(cls.name) ~ "\n");
                content.put("</h3>\n");

                if (cls.comments.length > 0)
                {
                    content.put("<div class=\"mb-4 pl-4 border-l-2 border-red-500/50\">\n");
                    content.put(formatComment(cls.comments));
                    content.put("</div>\n");
                }

                if (cls.fields.length > 0)
                {
                    content.put("<div class=\"mt-4\">\n");
                    content.put(
                            "<h4 class=\"text-sm font-semibold text-gray-400 uppercase tracking-wide mb-2\">Fields</h4>\n");
                    content.put("<div class=\"space-y-2\">\n");
                    foreach (field; cls.fields)
                    {
                        string privateClass = field.isPrivate ? " private-field" : "";
                        content.put("<div class=\"bg-code-bg rounded p-3 border border-border-color font-mono text-sm text-gray-300" ~ privateClass ~ "\">\n");
                        content.put(linkify(field.declaration) ~ "\n");
                        content.put("</div>\n");
                    }
                    content.put("</div>\n");
                    content.put("</div>\n");
                }

                if (cls.methods.length > 0)
                {
                    content.put("<div class=\"mt-4\">\n");
                    content.put(
                            "<h4 class=\"text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3\">Methods</h4>\n");
                    content.put("<div class=\"space-y-3\">\n");
                    foreach (func; cls.methods)
                    {
                        string methodId = cls.name ~ "." ~ func.name;
                        string privateClass = func.isPrivate ? " private-method" : "";
                        content.put(format(
                                "<div id=\"%s\" class=\"bg-code-bg rounded-lg p-4 border border-border-color%s\">\n",
                                escapeHTML(methodId), privateClass));
                        content.put("<div class=\"font-mono text-sm\">\n");
                        content.put(format("<span class=\"text-red-400\">%s</span> ",
                                escapeHTML(func.returnType)));
                        content.put(format("<span class=\"text-blue-400 font-semibold\">%s</span>",
                                escapeHTML(func.name)));
                        content.put("<span class=\"text-gray-500\">(");

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
                            content.put("<div class=\"mt-2 pl-3 border-l border-blue-500/50\">\n");
                            content.put(formatComment(func.comments));
                            content.put("</div>\n");
                        }
                        content.put("</div>\n");
                    }
                    content.put("</div>\n");
                    content.put("</div>\n");
                }

                content.put("</div>\n");
            }

            content.put("</div>\n");
            content.put("</section>\n");
        }

        if (mod.enums.length > 0)
        {
            content.put(
                    "<section class=\"bg-card-bg rounded-xl shadow-lg border border-border-color overflow-hidden\">\n");
            content.put("<div class=\"p-6 space-y-6\">\n");

            foreach (en; mod.enums)
            {
                content.put("<div class=\"bg-gray-800/40 rounded-lg p-6 border border-border-color hover:border-red-500/50 transition-colors\">\n");
                content.put(format(
                        "<h3 id=\"%s\" class=\"text-xl font-semibold text-cyan-400 mb-3 flex items-center gap-2\">\n",
                        escapeHTML(en.name)));
                content.put(
                        "<span class=\"text-gray-500 text-sm font-normal uppercase tracking-wide\">ENUM</span>\n");
                content.put(escapeHTML(en.name) ~ "\n");
                content.put("</h3>\n");

                if (en.comments.length > 0)
                {
                    content.put("<div class=\"mb-4 pl-4 border-l-2 border-red-500/50\">\n");
                    content.put(formatComment(en.comments));
                    content.put("</div>\n");
                }

                if (en.members.length > 0)
                {
                    content.put("<div class=\"mt-4\">\n");
                    content.put(
                            "<h4 class=\"text-sm font-semibold text-gray-400 uppercase tracking-wide mb-2\">Members</h4>\n");
                    content.put("<div class=\"space-y-2\">\n");
                    foreach (member; en.members)
                    {
                        content.put("<div class=\"bg-code-bg rounded p-3 border border-border-color font-mono text-sm text-gray-300\">\n");
                        content.put("<span class=\"text-blue-400 font-semibold\">" ~ escapeHTML(
                                member.name) ~ "</span>");
                        if (member.value.length > 0)
                        {
                            content.put(" = <span class=\"text-green-400\">" ~ escapeHTML(
                                    member.value) ~ "</span>");
                        }

                        if (member.comments.length > 0)
                        {
                            content.put(
                                    "<div class=\"mt-2 pl-3 border-l border-blue-500/50 text-gray-400\">\n");
                            content.put(formatComment(member.comments));
                            content.put("</div>\n");
                        }
                        content.put("</div>\n");
                    }
                    content.put("</div>\n");
                    content.put("</div>\n");
                }

                content.put("</div>\n");
            }

            content.put("</div>\n");
            content.put("</section>\n");
        }

        if (mod.functions.length > 0)
        {
            content.put(
                    "<section class=\"bg-card-bg rounded-xl shadow-lg border border-border-color overflow-hidden\">\n");
            content.put("<div class=\"p-6 space-y-4\">\n");

            foreach (func; mod.functions)
            {
                string privateClass = func.isPrivate ? " private-function" : "";
                content.put(format("<div id=\"%s\" class=\"bg-gray-800/40 rounded-lg p-5 border border-border-color hover:border-red-500/50 transition-colors%s\">\n",
                        escapeHTML(func.name), privateClass));
                content.put("<div class=\"font-mono text-sm\">\n");
                content.put(format("<span class=\"text-red-400\">%s</span> ",
                        escapeHTML(func.returnType)));
                content.put(format("<span class=\"text-blue-400 font-semibold text-base\">%s</span>",
                        escapeHTML(func.name)));
                content.put("<span class=\"text-gray-500\">(");

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
                    content.put("<div class=\"pl-4 border-l-2 border-red-500/50 mt-3\">\n");
                    content.put(formatComment(func.comments));
                    content.put("</div>\n");
                }

                content.put("</div>\n");
            }

            content.put("</div>\n");
            content.put("</section>\n");
        }

        string output = templateContent.replace("{{module_name}}", escapeHTML(mod.name));
        output = output.replace("{{content}}", content.data);

        f.write(output);
        f.close();
    }

    private string formatComment(string[] comments)
    {
        auto app = appender!string;
        bool insideParams = false;

        foreach (line; comments)
        {
            string trimmed = line.strip();

            if (trimmed == "Params:")
            {
                if (insideParams)
                    app.put("</ul>\n");
                insideParams = true;
                app.put("<div class=\"font-bold text-gray-200 mt-4 mb-2\">Params:</div>\n");
                app.put("<ul class=\"list-none pl-4 space-y-2 mb-4\">\n");
                continue;
            }

            if (trimmed.startsWith("Returns:"))
            {
                if (insideParams)
                {
                    app.put("</ul>\n");
                    insideParams = false;
                }

                string content = trimmed[8 .. $].strip();
                app.put(format("<div class=\"mt-4 text-gray-300\"><span class=\"font-bold text-gray-200\">Returns:</span> %s</div>\n",
                        escapeHTML(content)));
                continue;
            }

            if (insideParams)
            {
                if (trimmed.length == 0)
                    continue;

                auto eqPos = trimmed.indexOf('=');
                if (eqPos != -1)
                {
                    string pName = trimmed[0 .. eqPos].strip();
                    string pDesc = trimmed[eqPos + 1 .. $].strip();
                    app.put(format("<li><span class=\"font-mono text-blue-300 font-semibold\">%s</span> <span class=\"text-gray-400\">%s</span></li>\n",
                            escapeHTML(pName), escapeHTML(pDesc)));
                }
                else
                {
                    app.put(format("<div class=\"text-gray-400 ml-4\">%s</div>\n",
                            escapeHTML(trimmed)));
                }
            }
            else
            {
                if (trimmed.length > 0)
                    app.put(format("<p class=\"text-gray-300 leading-relaxed\">%s</p>\n",
                            escapeHTML(trimmed)));
            }
        }

        if (insideParams)
            app.put("</ul>\n");

        return app.data;
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
    string licenseType;
}

ProjectInfo detectProject(string path)
{
    ProjectInfo info;
    info.isDubProject = false;
    info.sourceDirectories = ["source", "src"];

    string dubJsonPath = buildPath(path, "dub.json");
    string dubSdlPath = buildPath(path, "dub.sdl");
    string licensePath = buildPath(path, "LICENSE");
    string licenseMdPath = buildPath(path, "LICENSE.md");

    if (exists(licensePath))
    {
        try
        {
            string content = readText(licensePath);
            if (content.canFind("MIT License"))
                info.licenseType = "MIT";
            else if (content.canFind("Apache License 2.0") || content.canFind("Apache-2.0"))
                info.licenseType = "Apache 2.0";
            else if (content.canFind("GNU General Public License") || content.canFind("GPL"))
                info.licenseType = "GNU General Public License";
            else if (content.canFind("BSD 3-Clause"))
                info.licenseType = "BSD 3-Clause";
            else if (content.canFind("BSD 2-Clause"))
                info.licenseType = "BSD 2-Clause";
            else if (content.canFind("ISC License"))
                info.licenseType = "ISC";
            else if (content.canFind("Mozilla Public License 2.0"))
                info.licenseType = "MPL 2.0";
            else if (content.canFind("The Unlicense"))
                info.licenseType = "Unlicense";
            else
                info.licenseType = "Custom License / Proprietary";
        }
        catch (Exception e)
        {
            writeln("Warning: Failed to read LICENSE file");
        }
    }
    else if (exists(licenseMdPath))
    {
        try
        {
            string content = readText(licenseMdPath);
            if (content.canFind("MIT License"))
                info.licenseType = "MIT";
            else if (content.canFind("Apache License 2.0") || content.canFind("Apache-2.0"))
                info.licenseType = "Apache 2.0";
            else if (content.canFind("GNU General Public License") || content.canFind("GPL"))
                info.licenseType = "GNU General Public License";
            else if (content.canFind("BSD 3-Clause"))
                info.licenseType = "BSD 3-Clause";
            else if (content.canFind("BSD 2-Clause"))
                info.licenseType = "BSD 2-Clause";
            else if (content.canFind("ISC License"))
                info.licenseType = "ISC";
            else if (content.canFind("Mozilla Public License 2.0"))
                info.licenseType = "MPL 2.0";
            else if (content.canFind("The Unlicense"))
                info.licenseType = "Unlicense";
            else
                info.licenseType = "Custom License / Proprietary";
        }
        catch (Exception e)
        {
            writeln("Warning: Failed to read LICENSE.md file");
        }
    }

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

/**
 * Find D files.
 *
 * Params:
 *   rootPath = The root path to search
 *
 * Returns: The string array of D file paths
 */
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

    if (args.canFind("--help") || args.canFind("-h"))
    {
        writeln("usage: ceres <dir-or-file>\n");
        writeln("  --version     display version info and exit");
        writeln("  --help        display this help and exit");
        return;
    }

    if (args.canFind("--version") || args.canFind("-v"))
    {
        writeln("v0.0.1");
        return;
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

    auto generator = new HTMLGenerator(modules, outputDir,
            toTitleCase(projectInfo.projectName), projectInfo.licenseType);
    generator.generate();

    writeln("Documentation generated successfully.");
    writeln("Open ", buildPath(outputDir, "index.html"), " to view");
}

private string toTitleCase(string input)
{
    import std.ascii;
    import std.string;
    import std.uni;
    import std.conv : to;

    auto words = input.toLower.split;

    string[] titleCasedWords;
    foreach (word; words)
    {
        titleCasedWords ~= word.asCapitalized.to!string;
    }

    return titleCasedWords.join(" ");
}
