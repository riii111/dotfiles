# dotfiles
## 1. nvim
<img width="1507" height="945" alt="image" src="https://github.com/user-attachments/assets/25cbf831-64df-40a5-9e22-4a5935ff1780" />

IntelliJ-like shortcuts available
<img width="1050" height="332" alt="image" src="https://github.com/user-attachments/assets/d904544c-0d7c-469f-8357-941f5824c78f" />

## 2. dbn/dbx
DB Client
<img width="1507" height="948" alt="image" src="https://github.com/user-attachments/assets/e69b298b-e0bb-4d87-a9da-fe0e1641af37" />

### prepare

Place directly under the project. example↓
```toml
default = "app_ro"

[profiles.app_ro]
dsn = "postgres://app:app@localhost:15432/app?sslmode=disable"
```
