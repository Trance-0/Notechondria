"""I want to make a cmd chatter here, but don't want to do it anymore."""
# def generate_message_raw():
#     """ Void function that generate the AI response given the conversation
#     This function is the raw version of request that will fit any api.
#     """
#     import base64
#     import requests
#     def encode_image(image_path):
#         """Function to encode the image"""
#         with open(image_path, "rb") as image_file:
#             return base64.b64encode(image_file.read()).decode("utf-8")
#     headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}
#     payload = {
#         "model": "gpt-4-vision-preview",
#         "messages": [
#             i.to_dict() for i in message_list
#         ],
#         "max_tokens": conversation.max_token,
#     }
#     response = requests.post(
#         "https://api.openai.com/v1/chat/completions",
#         headers=headers,
#         json=payload,
#     )
#     logger.info(payload)
#     logger.info(response.json())
#     json_res = response.json()
#     # generate response msg to conversation
#     if not "error" in response:
#         # update token count
#         conversation.total_prompt_tokens+=json_res["usage"]["prompt_tokens"]
#         conversation.total_completion_tokens+=json_res["usage"]["completion_tokens"]
#         conversation.save()
#         response_choices=json_res["choices"]
#         Message.objects.create(conversation_id=conversation,role=MessageRoleChoices.ASSISTANT,text=response_choices[0]["message"]["content"])
#     return json_res