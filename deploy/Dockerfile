FROM barichello/godot-ci:4.6.3
# reuse the same pinned binary used by CI — guarantees parity

WORKDIR /app
COPY . .

# Pre-warm the .godot/ import cache so the first player connection is fast.
# The editor templates are not present in this image; the harmless warning is suppressed.
RUN godot --headless --import 2>/dev/null; true

EXPOSE 9000

CMD ["godot", "--headless", "--", "--server", "--port=9000"]
