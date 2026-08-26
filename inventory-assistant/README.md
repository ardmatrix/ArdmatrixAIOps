# AIOps Expert

Read-only natural-language access to ARDMATRIX inventory and current operational health.

## API

- `GET /health`
- `POST /chat`
- Chat interface: `http://localhost:8090/`
- Interactive API documentation: `http://localhost:8090/docs`

Example request:

```json
{
  "message": "Which data centers have critical assets and how many servers are affected?"
}
```

Common questions use a direct database fast path. Complex questions use `gpt-5.4-mini`
through the OpenAI API. Set `OPENAI_API_KEY` in the local `.env` file; never commit it.
`LLM_MODEL`, `LLM_BASE_URL`, and reasoning effort remain configurable. The database session
is forced to read-only mode, has a five-second statement timeout, and exposes only
allowlisted inventory queries. Arbitrary model-generated SQL is not accepted.
