---
type: llm
focus: { source: file, path: src/Controller/DocumentController.php }
---

PASS if the controller no longer uses getClientOriginalName() for the stored file name, stores files outside public/, and validates size and type (Assert\File constraint, MapUploadedFile or an equivalent check). FAIL otherwise.
