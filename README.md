1. Review PR
   > review <pr-link> 

2. Analyze the failed case in ci
   > ci-diagnose <pr-link> 

3. Development based on design doc
   > dev-with-doc xxx.md <--desc "xx">

4. review code based on design doc
   > review-self <rfc-xxx.md>

5. write design doc based on discussion
   > write-design-doc <design-name>

6. write design doc based on discussion, then develop based on design, and review code
   > ship-with-doc <feature-slug> --title "xx" --desc "xx"
