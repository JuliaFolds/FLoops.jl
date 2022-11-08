module Utils

struct NoError end

macro macroexpand_error(ex)
    @gensym err
    quote
        try
            $Base.@eval $Base.@macroexpand $ex
            $NoError()
        catch $err
            $err
        end
    end |> esc
end

end  # module
