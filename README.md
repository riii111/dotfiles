# dotfiles
## 1. nvim
<img width="1511" height="942" alt="image" src="https://github.com/user-attachments/assets/6cf9e4a2-8d24-4547-81f4-d30bff35185a" />

IntelliJ-like shortcuts available
<img width="1013" height="196" alt="image" src="https://github.com/user-attachments/assets/da51445c-1d46-4980-a469-fc094a2ba3f8" />

## 2. dbn/dbx（DB Client）
Access the database with just one command
<img width="1507" height="948" alt="image" src="https://github.com/user-attachments/assets/e69b298b-e0bb-4d87-a9da-fe0e1641af37" />

### prepare

Place directly under the project. example↓
```toml
default = "app_ro"

[profiles.app_ro]
dsn = "postgres://app:app@localhost:15432/app?sslmode=disable"
```

and add the line `.zshrc`:
```bash
export PATH="$HOME/bin:$PATH"
```
