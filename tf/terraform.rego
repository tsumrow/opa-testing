package terraform.analysis

import input as tfplan

########################
# Parameters for Policy
########################

# acceptable score for automated authorization
blast_radius = 30

# weights assigned for each operation on each resource-type
weights = {
    "aws_autoscaling_group": {"delete": 100, "create": 10, "modify": 1},
    "aws_instance": {"delete": 10, "create": 1, "modify": 1}
}

# Consider exactly these resource types in calculations
resource_types = {"aws_autoscaling_group", "aws_instance", "aws_iam", "aws_launch_configuration"}

#########
# Policy
#########

# Authorization holds if score for the plan is acceptable and no changes are made to IAM
default authz = false
authz {
    score < blast_radius
    not touches_iam
}

# Compute the score for a Terraform plan as the weighted sum of deletions, creations, modifications
score = s {
    all = [ x | 
            weights[resource_type] = crud;
            del = crud["delete"] * num_deletes[resource_type];
            new = crud["create"] * num_creates[resource_type];
            mod = crud["modify"] * num_modifies[resource_type];
            x1 = del + new
            x = x1 + mod
    ]
    sum(all, s)
}

# Whether there is any change to IAM
touches_iam {
    all = instance_names["aws_iam"]
    count(all, c)
    c > 0
}

####################
# Terraform Library
####################

# list of all resources of a given type
instance_names[resource_type] = all {
    resource_types[resource_type]
    all = [name |
        tfplan[name] = _
        startswith(name, resource_type)
    ]
}

# number of deletions of resources of a given type
num_deletes[resource_type] = num {
    resource_types[resource_type]
    all = instance_names[resource_type]
    deletions = [name | all[_] = name; tfplan[name]["destroy"] = true]
    count(deletions, num)
}

# number of creations of resources of a given type
num_creates[resource_type] = num {
    resource_types[resource_type]
    all = instance_names[resource_type]
    creates = [name | all[_] = name; tfplan[name]["id"] = ""]
    count(creates, num)
}

# number of modifications to resources of a given type
num_modifies[resource_type] = num {
    resource_types[resource_type]
    all = instance_names[resource_type]
    modifies = [name | all[_] = name; obj = tfplan[name]; obj["destroy"] = false; not obj["id"]]
    count(modifies, num)
}