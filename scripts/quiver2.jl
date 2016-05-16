import Bio.Seq
@everywhere using Bio.Seq
using ArgParse
using Glob

import Quiver2.Model
import Quiver2.QIO
@everywhere using Quiver2.Model
@everywhere using Quiver2.QIO

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--prefix"
        help = "prepended to each filename to make label"
        arg_type = AbstractString
        default = ""

        "--keep-unique-name"
        help = "keep only unique middle part of filename"
        action = :store_true

        "--bandwidth"
        help = "alignment bandwidth"
        arg_type = Int
        default = 10

        "--min-dist"
        help = "minimum distance between mutations"
        arg_type = Int
        default = 9

        "--batch"
        help = "batch size; -1 for no batch iterations"
        arg_type = Int
        default = 10

        "--max-iters"
        help = "maximum iterations before giving up"
        arg_type = Int
        default = 100

        "--verbose", "-v"
        help = "print progress"
        action = :store_true

        "log_ins"
        help = "log10 insertion probability"
        arg_type = Float64
        required = true

        "log_del"
        help = "log10 deletion probability"
        arg_type = Float64
        required = true

        "input"
        help = "a single file or a glob. each filename should be unique."
        required = true
    end
    return parse_args(s)
end

@everywhere function dofile(file, args)
    if args["verbose"]
        print(STDERR, "reading sequences from '$(file)'\n")
    end
    sequences, log_ps = read_fastq(file)
    template = sequences[1]
    if args["verbose"]
        print(STDERR, "starting run\n")
    end
    consensus, info = quiver2(template, sequences, log_ps,
                              args["log_ins"], args["log_del"],
                              bandwidth=args["bandwidth"], min_dist=args["min-dist"],
                              batch=args["batch"], max_iters=args["max-iters"],
                              verbose=args["verbose"])
    return consensus
end

function common_prefix(strings)
    minlen = minimum([length(s) for s in strings])
    cand = strings[1][1:minlen]
    x = 0
    for i = 1:minlen
        if all([s[i] == cand[i] for s in strings])
            x = i
	else
	    break
        end
    end
    return cand[1:x]
end

function common_suffix(strings)
    return reverse(common_prefix([reverse(s) for s in strings]))
end

function main()
    args = parse_commandline()
    input = args["input"]

    dir, pattern = splitdir(input)
    infiles = glob(pattern, dir)
    if length(infiles) == 0
       return
    end
    names = [splitext(basename(f))[1] for f in infiles]
    if length(Set(names)) != length(names)
        error("Files do not have unique names")
    end

    @everywhere function f(x)
        return dofile(x, args)
    end
    results = pmap((f, a) -> dofile(f, a), infiles, [args for i in 1:length(infiles)])

    plen = 0
    slen = 0
    if args["keep-unique-name"]
        plen = length(common_prefix(names))
	slen = length(common_suffix(names))
    end

    prefix = args["prefix"]
    for i=1:length(results)
        name = names[i]
        if args["keep-unique-name"]
            name = name[plen + 1:end - slen]
        end
        label = string(prefix, name)
        write(STDOUT, Seq.FASTASeqRecord(label, results[i], Seq.FASTAMetadata("")))
    end
end

main()
