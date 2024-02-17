from openai import OpenAI
client = OpenAI()

print(client.models.list())
