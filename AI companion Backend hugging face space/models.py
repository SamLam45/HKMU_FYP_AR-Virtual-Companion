from typing import List, Dict
from pydantic import BaseModel

class AnalysisRequest(BaseModel):
    user_id: str
    qa_list: List[Dict[str, str]]
