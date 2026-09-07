from sqlmodel import SQLModel

#Token modeli

class Token(SQLModel):
    access_token: str
    token_type: str
