# Start MOM

From the repository root:

```bash
cd runtime/text_mvp
bash start_mom.sh
```

That command will:

1. use the local 8B abliterated GGUF if it exists;
2. download it automatically if it does not;
3. start llama.cpp locally on port 8080;
4. start MOM's texting interface on port 7331.

Open:

`http://127.0.0.1:7331`

MOM's local chat history persists in `runtime/text_mvp/mom_local.db`.
