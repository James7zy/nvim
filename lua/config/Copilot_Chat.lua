{
  -- Uses visual selection or falls back to buffer
  selection = function(source)
    return select.visual(source) or select.buffer(source)
  end
}

