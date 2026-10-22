# Railway CLI rules

- Never print, echo, or cat token values.
- Never read `.env` contents; refer to key names only.
- Never commit real project names, IDs, or emails; fixtures use placeholders.
- Deletes always go through `--confirm <name>`.
