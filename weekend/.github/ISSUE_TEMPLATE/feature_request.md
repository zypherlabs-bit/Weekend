name: Feature Request
description: Suggest a new feature
title: "[Feature] "
labels: ["feature"]
body:
  - type: textarea
    attributes:
      label: Problem
      description: What problem does this solve?
    validations:
      required: true
  - type: textarea
    attributes:
      label: Proposed Solution
      description: Describe your proposed solution
    validations:
      required: true
  - type: textarea
    attributes:
      label: Alternatives Considered
      description: Other solutions you've considered
  - type: textarea
    attributes:
      label: Additional Context
      description: Mockups, references, etc.
