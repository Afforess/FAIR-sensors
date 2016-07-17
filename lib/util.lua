local wrapper = function(wrap)
    return function(msg, options)
        if not options or not options.comments then
            if options then
                options.comment = false
                return wrap(msg, options)
            else
                return wrap(msg, {comment = false})
            end
        end
        return wrap(msg, options)
    end
end

_ENV.serpent.line = wrapper(serpent.line)
_ENV.serpent.block = wrapper(serpent.block)
_ENV.serpent.dump = wrapper(serpent.dump)
